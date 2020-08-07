import tables, algorithm, sets, sequtils

type
  # facts
  Field* = enum
    Identifier, Attribute, Value
  Fact[T] = tuple[id: T, attr: T, value: T]
  TokenKind = enum
    Insert, Retract, Update
  Token[T] = object
    fact: Fact[T]
    case kind: TokenKind
    of Insert, Retract:
      nil
    of Update:
      oldFact: Fact[T]
  IdAttr = tuple[id: int, attr: int]
  IdAttrs = seq[IdAttr]

  # matches
  Vars*[T] = Table[string, T]
  Var* = object
    name*: string
    field: Field
  Match[MatchT] = object
    id: int
    vars: MatchT
    enabled: bool

  # functions
  CallbackFn[MatchT] = proc (vars: MatchT)
  SessionCallbackFn[T, MatchT] = proc (session: var Session[T, MatchT], vars: MatchT)
  QueryFn[MatchT, U] = proc (vars: MatchT): U
  FilterFn[MatchT] = proc (vars: MatchT): bool
  InitMatchFn[MatchT] = proc (ruleName: string): MatchT

  # alpha network
  AlphaNode[T, MatchT] = ref object
    testField: Field
    testValue: T
    facts: Table[int, Table[int, Fact[T]]]
    successors: seq[JoinNode[T, MatchT]]
    children: seq[AlphaNode[T, MatchT]]

  # beta network
  MemoryNodeType = enum
    Partial, Leaf
  MemoryNode[T, MatchT] = ref object
    parent: JoinNode[T, MatchT]
    child: JoinNode[T, MatchT]
    leafNode: MemoryNode[T, MatchT]
    lastMatchId: int
    matches: Table[IdAttrs, Match[MatchT]]
    matchIds: Table[int, IdAttrs]
    condition: Condition[T, MatchT]
    case nodeType: MemoryNodeType
      of Leaf:
        callback: CallbackFn[MatchT]
        trigger: bool
        filter: FilterFn[MatchT]
      else:
        nil
  JoinNode[T, MatchT] = ref object
    parent: MemoryNode[T, MatchT]
    child: MemoryNode[T, MatchT]
    alphaNode: AlphaNode[T, MatchT]
    condition: Condition[T, MatchT]
    idName: string
    oldIdAttrs: HashSet[IdAttr]
    disableFastUpdates: bool
    ruleName: string

  # session
  Condition[T, MatchT] = object
    nodes: seq[AlphaNode[T, MatchT]]
    vars: seq[Var]
    shouldTrigger: bool
  Production*[T, U, MatchT] = object
    callback: SessionCallbackFn[T, MatchT]
    conditions: seq[Condition[T, MatchT]]
    query: QueryFn[MatchT, U]
    name: string
    filter: FilterFn[MatchT]
  Session*[T, MatchT] = object
    alphaNode: AlphaNode[T, MatchT]
    leafNodes: ref Table[string, MemoryNode[T, MatchT]]
    idAttrNodes: ref Table[IdAttr, HashSet[ptr AlphaNode[T, MatchT]]]
    insideRule*: bool
    thenQueue: ref HashSet[tuple[node: ptr MemoryNode[T, MatchT], idAttrs: IdAttrs]]
    autoFire: bool
    initMatch: InitMatchFn[MatchT]

proc addNode(node: AlphaNode, newNode: AlphaNode): AlphaNode =
  for child in node.children:
    if child.testField == newNode.testField and child.testValue == newNode.testValue:
      return child
  node.children.add(newNode)
  return newNode

proc addNodes(session: Session, nodes: seq[AlphaNode]): AlphaNode =
  result = session.alphaNode
  for node in nodes:
    result = result.addNode(node)

proc add*[T, U, MatchT](production: var Production[T, U, MatchT], id: Var or T, attr: T, value: Var or T, then: bool) =
  var condition = Condition[T, MatchT](shouldTrigger: then)
  for fieldType in [Field.Identifier, Field.Attribute, Field.Value]:
    case fieldType:
      of Field.Identifier:
        when id is T:
          condition.nodes.add AlphaNode[T, MatchT](testField: fieldType, testValue: id)
        else:
          var temp = id
          temp.field = fieldType
          condition.vars.add(temp)
      of Field.Attribute:
        condition.nodes.add AlphaNode[T, MatchT](testField: fieldType, testValue: attr)
      of Field.Value:
        when value is T:
          condition.nodes.add AlphaNode[T, MatchT](testField: fieldType, testValue: value)
        else:
          var temp = value
          temp.field = fieldType
          condition.vars.add(temp)
  production.conditions.add(condition)

proc isAncestor(x, y: JoinNode): bool =
  var node = y
  while node != nil and node.parent != nil:
    if node.parent.parent == x:
      return true
    else:
      node = node.parent.parent
  false

proc add*[T, U, MatchT](session: Session[T, MatchT], production: Production[T, U, MatchT]) =
  var memNodes: seq[MemoryNode[T, MatchT]]
  var joinNodes: seq[JoinNode[T, MatchT]]
  let last = production.conditions.len - 1
  var
    bindings: HashSet[string]
    joinedBindings: HashSet[string]
  for i in 0 .. last:
    var condition = production.conditions[i]
    var leafAlphaNode = session.addNodes(condition.nodes)
    let parentMemNode = if memNodes.len > 0: memNodes[memNodes.len - 1] else: nil
    var joinNode = JoinNode[T, MatchT](parent: parentMemNode, alphaNode: leafAlphaNode, condition: condition, ruleName: production.name)
    for v in condition.vars:
      if bindings.contains(v.name):
        joinedBindings.incl(v.name)
        if v.field == Identifier:
          joinNode.idName = v.name
      else:
        bindings.incl(v.name)
    if parentMemNode != nil:
      parentMemNode.child = joinNode
    leafAlphaNode.successors.add(joinNode)
    # successors must be sorted by ancestry (descendents first) to avoid duplicate rule firings
    leafAlphaNode.successors.sort(proc (x, y: JoinNode[T, MatchT]): int =
      if isAncestor(x, y): 1 else: -1)
    var memNode = MemoryNode[T, MatchT](parent: joinNode, nodeType: if i == last: Leaf else: Partial, condition: condition, lastMatchId: -1)
    if memNode.nodeType == Leaf:
      memNode.filter = production.filter
      if production.callback != nil:
        var sess = session
        memNode.callback = proc (vars: MatchT) = production.callback(sess, vars)
      if session.leafNodes.hasKey(production.name):
        raise newException(Exception, production.name & " already exists in session")
      session.leafNodes[production.name] = memNode
    memNodes.add(memNode)
    joinNodes.add(joinNode)
    joinNode.child = memNode
  let leafMemNode = memNodes[memNodes.len - 1]
  for node in memNodes:
    node.leafNode = leafMemNode
  for node in joinNodes:
    # disable fast updates for facts whose value is part of a join
    for v in node.condition.vars:
      if v.field == Value and joinedBindings.contains(v.name):
        node.disableFastUpdates = true
        break

proc getVarFromFact[T, MatchT](vars: var MatchT, key: string, fact: T): bool =
  if vars.hasKey(key) and vars[key] != fact:
    return false
  vars[key] = fact
  true

proc getVarsFromFact[T, MatchT](vars: var MatchT, condition: Condition[T, MatchT], fact: Fact[T]): bool =
  for v in condition.vars:
    case v.field:
      of Identifier:
        if not getVarFromFact(vars, v.name, fact[0]):
          return false
      of Attribute:
        raise newException(Exception, "Attributes can not contain vars: " & $v)
      of Value:
        if not getVarFromFact(vars, v.name, fact[2]):
          return false
  true

proc getIdAttr[T](fact: Fact[T]): IdAttr =
  let
    id = fact.id.type0
    attr = fact.attr.type1.ord
  (id, attr)

proc leftActivation[T, MatchT](session: var Session[T, MatchT], node: var MemoryNode[T, MatchT], idAttrs: IdAttrs, vars: MatchT, token: Token[T], isNew: bool)

proc leftActivation[T, MatchT](session: var Session[T, MatchT], node: JoinNode[T, MatchT], idAttrs: IdAttrs, vars: MatchT, token: Token[T], alphaFact: Fact[T]) =
  var newVars = vars
  if getVarsFromFact(newVars, node.condition, alphaFact):
    let idAttr = alphaFact.getIdAttr
    var newIdAttrs = idAttrs
    newIdAttrs.add(idAttr)
    var newToken = token
    newToken.fact = alphaFact
    let isNew = not node.oldIdAttrs.contains(idAttr)
    session.leftActivation(node.child, newIdAttrs, newVars, newToken, isNew)

proc leftActivation[T, MatchT](session: var Session[T, MatchT], node: JoinNode[T, MatchT], idAttrs: IdAttrs, vars: MatchT, token: Token[T]) =
  # SHORTCUT: if we know the id, only loop over alpha facts with that id
  if node.idName != "":
    let id = vars[node.idName].type0
    if node.alphaNode.facts.hasKey(id):
      for alphaFact in node.alphaNode.facts[id].values:
        session.leftActivation(node, idAttrs, vars, token, alphaFact)
  else:
    for factsForId in node.alphaNode.facts.values:
      for alphaFact in factsForId.values:
        session.leftActivation(node, idAttrs, vars, token, alphaFact)

proc leftActivation[T, MatchT](session: var Session[T, MatchT], node: var MemoryNode[T, MatchT], idAttrs: IdAttrs, vars: MatchT, token: Token[T], isNew: bool) =
  let idAttr = idAttrs[idAttrs.len-1]
  # if the insert/update fact is new and this condition doesn't have then = false, let the leaf node trigger
  if isNew and (token.kind == Insert or token.kind == Update) and node.condition.shouldTrigger:
    node.leafNode.trigger = true
  # add or remove the match
  case token.kind:
  of Insert, Update:
    var match =
      if node.matches.hasKey(idAttrs):
        node.matches[idAttrs]
      else:
        node.lastMatchId += 1
        Match[MatchT](id: node.lastMatchId)
    match.vars = vars
    match.enabled = node.nodeType != Leaf or node.filter == nil or node.filter(vars)
    node.matchIds[match.id] = idAttrs
    node.matches[idAttrs] = match
    if node.nodeType == Leaf and node.trigger and node.callback != nil:
      session.thenQueue[].incl((node.addr, idAttrs))
    node.parent.oldIdAttrs.incl(idAttr)
  of Retract:
    node.matchIds.del(node.matches[idAttrs].id)
    node.matches.del(idAttrs)
    node.parent.oldIdAttrs.excl(idAttr)
  # pass the token down the chain
  if node.nodeType != Leaf:
    session.leftActivation(node.child, idAttrs, vars, token)

proc rightActivation[T, MatchT](session: var Session[T, MatchT], node: JoinNode[T, MatchT], idAttr: IdAttr, token: Token[T]) =
  if node.parent == nil: # root node
    var vars = session.initMatch(node.ruleName)
    if getVarsFromFact(vars, node.condition, token.fact):
      session.leftActivation(node.child, @[idAttr], vars, token, true)
  else:
    for idAttrs, match in node.parent.matches.pairs:
      let vars = match.vars
      # SHORTCUT: if we know the id, compare it with the token right away
      if node.idName != "" and vars[node.idName].type0 != token.fact.id.type0:
        continue
      var newVars = vars # making a mutable copy here is far faster than making `vars` mutable above
      if getVarsFromFact(newVars, node.condition, token.fact):
        var newIdAttrs = idAttrs
        newIdAttrs.add(idAttr)
        session.leftActivation(node.child, newIdAttrs, newVars, token, true)

proc rightActivation[T, MatchT](session: var Session[T, MatchT], node: var AlphaNode[T, MatchT], token: Token[T]) =
  let idAttr = token.fact.getIdAttr
  case token.kind:
  of Insert:
    if not node.facts.hasKey(idAttr.id):
      node.facts[idAttr.id] = initTable[int, Fact[T]]()
    node.facts[idAttr.id][idAttr.attr] = token.fact
    if not session.idAttrNodes.hasKey(idAttr):
      session.idAttrNodes[idAttr] = initHashSet[ptr AlphaNode[T, MatchT]](initialSize = 4)
    let exists = session.idAttrNodes[idAttr].containsOrIncl(node.addr)
    assert not exists
  of Retract:
    node.facts[idAttr.id].del(idAttr.attr)
    let missing = session.idAttrNodes[idAttr].missingOrExcl(node.addr)
    assert not missing
  of Update:
    assert node.facts[idAttr.id][idAttr.attr] == token.oldFact
    node.facts[idAttr.id][idAttr.attr] = token.fact
  for child in node.successors:
    if token.kind == Update and child.disableFastUpdates:
      session.rightActivation(child, idAttr, Token[T](fact: token.oldFact, kind: Retract))
      session.rightActivation(child, idAttr, Token[T](fact: token.fact, kind: Insert))
    else:
      session.rightActivation(child, idAttr, token)

proc fireRules*[T, MatchT](session: var Session[T, MatchT]) =
  # find all nodes with `then` blocks that need executed
  var thenQueue: seq[(ptr MemoryNode[T, MatchT], MatchT)]
  for (node, idAttrs) in session.thenQueue[].items:
    node.trigger = false
    if node.matches.hasKey(idAttrs):
      let match = node.matches[idAttrs]
      if match.enabled:
        thenQueue.add((node, match.vars))
  if thenQueue.len == 0:
    return
  session.thenQueue[].clear
  # execute `then` blocks
  for (node, vars) in thenQueue:
    node[].callback(vars)
  # recur because there may be new `then` blocks to execute
  session.fireRules()

proc getAlphaNodesForFact[T, MatchT](session: var Session[T, MatchT], node: var AlphaNode[T, MatchT], fact: Fact[T], root: bool, nodes: var HashSet[ptr AlphaNode[T, MatchT]]) =
  if root:
    for child in node.children.mitems:
      session.getAlphaNodesForFact(child, fact, false, nodes)
  else:
    let val = case node.testField:
      of Field.Identifier: fact[0]
      of Field.Attribute: fact[1]
      of Field.Value: fact[2]
    if val != node.testValue:
      return
    nodes.incl(node.addr)
    for child in node.children.mitems:
      session.getAlphaNodesForFact(child, fact, false, nodes)

proc upsertFact[T, MatchT](session: var Session[T, MatchT], fact: Fact[T], nodes: HashSet[ptr AlphaNode[T, MatchT]]) =
  let idAttr = fact.getIdAttr
  if not session.idAttrNodes.hasKey(idAttr):
    for n in nodes.items:
      session.rightActivation(n[], Token[T](fact: fact, kind: Insert))
  else:
    let existingNodes = session.idAttrNodes[idAttr]
    # retract any facts from nodes that the new fact wasn't inserted in
    # we use toSeq here to make a copy of the existingNodes, because
    # rightActivation will modify it
    for n in existingNodes.items.toSeq:
      if not nodes.contains(n):
        let oldFact = n.facts[fact.id.type0][fact.attr.type1.ord]
        session.rightActivation(n[], Token[T](fact: oldFact, kind: Retract))
    # update or insert facts, depending on whether the node already exists
    for n in nodes.items:
      if existingNodes.contains(n):
        let oldFact = n.facts[fact.id.type0][fact.attr.type1.ord]
        session.rightActivation(n[], Token[T](fact: fact, kind: Update, oldFact: oldFact))
      else:
        session.rightActivation(n[], Token[T](fact: fact, kind: Insert))

proc insertFact*[T, MatchT](session: var Session[T, MatchT], fact: Fact[T]) =
  var nodes = initHashSet[ptr AlphaNode[T, MatchT]](initialSize = 4)
  getAlphaNodesForFact(session, session.alphaNode, fact, true, nodes)
  session.upsertFact(fact, nodes)
  if session.autoFire and not session.insideRule:
    session.fireRules()

proc retractFact*[T, MatchT](session: var Session[T, MatchT], fact: Fact[T]) =
  let idAttr = fact.getIdAttr
  # we use toSeq here to make a copy of idAttrNodes[idAttr], since
  # rightActivation will modify it
  for node in session.idAttrNodes[idAttr].items.toSeq:
    assert fact == node.facts[idAttr.id][idAttr.attr]
    session.rightActivation(node[], Token[T](fact: fact, kind: Retract))

proc retractFact*[T, MatchT](session: var Session[T, MatchT], id: T, attr: T) =
  let id = id.type0
  let attr = attr.type1.ord
  let idAttr = (id, attr)
  # we use toSeq here to make a copy of idAttrNodes[idAttr], since
  # rightActivation will modify it
  for node in session.idAttrNodes[idAttr].items.toSeq:
    let fact = node.facts[id][attr]
    session.rightActivation(node[], Token[T](fact: fact, kind: Retract))

proc defaultInitMatch[MatchT](ruleName: string): MatchT =
  MatchT()

proc initSession*[T, MatchT](autoFire: bool = true, initMatch: InitMatchFn[MatchT] = defaultInitMatch): Session[T, MatchT] =
  result.alphaNode = new(AlphaNode[T, MatchT])
  result.leafNodes = newTable[string, MemoryNode[T, MatchT]]()
  result.idAttrNodes = newTable[IdAttr, HashSet[ptr AlphaNode[T, MatchT]]]()
  new result.thenQueue
  result.thenQueue[] = initHashSet[(ptr MemoryNode[T, MatchT], IdAttrs)]()
  result.autoFire = autoFire
  result.initMatch = initMatch

proc initProduction*[T, U, MatchT](name: string, cb: SessionCallbackFn[T, MatchT], query: QueryFn[MatchT, U], filter: FilterFn[MatchT]): Production[T, U, MatchT] =
  result.name = name
  result.callback = cb
  result.query = query
  result.filter = filter

proc matchesParams[I, T, MatchT](vars: MatchT, params: array[I, (string, T)]): bool =
  for (varName, val) in params:
    if vars[varname] != val:
      return false
  true

proc findIndex*[I, T](session: Session, prod: Production, params: array[I, (string, T)]): int =
  for match in session.leafNodes[prod.name].matches.values:
    if match.enabled and matchesParams(match.vars, params):
      return match.id
  -1

proc findIndex*(session: Session, prod: Production): int =
  for match in session.leafNodes[prod.name].matches.values:
    if match.enabled:
      return match.id
  -1

proc findAllIndices*[I, T](session: Session, prod: Production, params: array[I, (string, T)]): seq[int] =
  for match in session.leafNodes[prod.name].matches.values:
    if match.enabled and matchesParams(match.vars, params):
      result.add(match.id)

proc findAllIndices*(session: Session, prod: Production): seq[int] =
  for match in session.leafNodes[prod.name].matches.values:
    if match.enabled:
      result.add(match.id)

proc get*[T, U, MatchT](session: Session[T, MatchT], prod: Production[T, U, MatchT], i: int): U =
  let idAttrs = session.leafNodes[prod.name].matchIds[i]
  prod.query(session.leafNodes[prod.name].matches[idAttrs].vars)
