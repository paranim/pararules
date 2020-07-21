import strformat, tables, algorithm, sets, sequtils

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
  Vars[T] = Table[string, T]
  Var* = object
    name*: string
    field: Field
  Match[T] = object
    id: int
    vars: Vars[T]
    enabled: bool
    trigger: bool

  # functions
  CallbackFn[T] = proc (vars: Vars[T])
  SessionCallbackFn[T] = proc (session: var Session[T], vars: Vars[T])
  QueryFn[T, U] = proc (vars: Vars[T]): U
  FilterFn[T] = proc (vars: Vars[T]): bool

  # alpha network
  AlphaNode[T] = ref object
    testField: Field
    testValue: T
    facts: Table[int, Table[int, Fact[T]]]
    successors: seq[JoinNode[T]]
    children: seq[AlphaNode[T]]

  # beta network
  MemoryNodeType = enum
    Partial, Leaf
  MemoryNode[T] = ref object
    parent: JoinNode[T]
    child: JoinNode[T]
    leafNode: MemoryNode[T]
    lastMatchId: int
    matches: Table[IdAttrs, Match[T]]
    matchIds: Table[int, IdAttrs]
    condition: Condition[T]
    case nodeType: MemoryNodeType
      of Leaf:
        callback: CallbackFn[T]
        trigger: bool
        filter: FilterFn[T]
      else:
        nil
  JoinNode[T] = ref object
    parent: MemoryNode[T]
    child: MemoryNode[T]
    alphaNode: AlphaNode[T]
    condition: Condition[T]
    idName: string

  # session
  Condition[T] = object
    nodes: seq[AlphaNode[T]]
    vars: seq[Var]
    shouldTrigger: bool
  Production*[T, U] = object
    callback: SessionCallbackFn[T]
    conditions: seq[Condition[T]]
    query: QueryFn[T, U]
    name: string
    filter: FilterFn[T]
  Session*[T] = object
    alphaNode: AlphaNode[T]
    leafNodes: ref Table[string, MemoryNode[T]]
    idAttrNodes: ref Table[IdAttr, HashSet[ptr AlphaNode[T]]]
    insideRule*: bool
    thenNodes: ref HashSet[ptr MemoryNode[T]]
    autoFire: bool

proc getParent*(node: MemoryNode): MemoryNode =
  node.parent.parent

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

proc add*[T, U](production: var Production[T, U], id: Var or T, attr: T, value: Var or T, then: bool) =
  var condition = Condition[T](shouldTrigger: then)
  for fieldType in [Field.Identifier, Field.Attribute, Field.Value]:
    case fieldType:
      of Field.Identifier:
        when id is T:
          condition.nodes.add AlphaNode[T](testField: fieldType, testValue: id)
        else:
          var temp = id
          temp.field = fieldType
          condition.vars.add(temp)
      of Field.Attribute:
        condition.nodes.add AlphaNode[T](testField: fieldType, testValue: attr)
      of Field.Value:
        when value is T:
          condition.nodes.add AlphaNode[T](testField: fieldType, testValue: value)
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

proc add*[T, U](session: Session[T], production: Production[T, U]) =
  var memNodes: seq[MemoryNode[T]]
  let last = production.conditions.len - 1
  var
    bindings: HashSet[string]
    joinedBindings: HashSet[string]
  for i in 0 .. last:
    var condition = production.conditions[i]
    var leafAlphaNode = session.addNodes(condition.nodes)
    let parentMemNode = if memNodes.len > 0: memNodes[memNodes.len - 1] else: nil
    var joinNode = JoinNode[T](parent: parentMemNode, alphaNode: leafAlphaNode, condition: condition)
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
    leafAlphaNode.successors.sort(proc (x, y: JoinNode[T]): int =
      if isAncestor(x, y): 1 else: -1)
    var memNode = MemoryNode[T](parent: joinNode, nodeType: if i == last: Leaf else: Partial, condition: condition)
    if memNode.nodeType == Leaf:
      memNode.filter = production.filter
      if production.callback != nil:
        var sess = session
        memNode.callback = proc (vars: Vars[T]) = production.callback(sess, vars)
      if session.leafNodes.hasKey(production.name):
        raise newException(Exception, production.name & " already exists in session")
      session.leafNodes[production.name] = memNode
    memNodes.add(memNode)
    joinNode.child = memNode
  let leafMemNode = memNodes[memNodes.len - 1]
  for node in memNodes:
    node.leafNode = leafMemNode

proc getVarsFromFact[T](vars: var Vars[T], condition: Condition[T], fact: Fact[T]): bool =
  for v in condition.vars:
    case v.field:
      of Identifier:
        if vars.hasKey(v.name) and vars[v.name].type0 != fact[0].type0:
          return false
        else:
          vars[v.name] = fact[0]
      of Attribute:
        raise newException(Exception, "Attributes can not contain vars: " & $v)
      of Value:
        if vars.hasKey(v.name) and vars[v.name] != fact[2]:
          return false
        else:
          vars[v.name] = fact[2]
  true

proc getIdAttr[T](fact: Fact[T]): IdAttr =
  let
    id = fact.id.type0
    attr = fact.attr.type1.ord
  (id, attr)

proc leftActivation[T](session: var Session[T], node: var MemoryNode[T], idAttrs: IdAttrs, vars: Vars[T], token: Token[T], fromAlpha: bool)

proc leftActivation[T](session: var Session[T], node: JoinNode[T], idAttrs: IdAttrs, vars: Vars[T], token: Token[T]) =
  # SHORTCUT: if we know the id, only loop over alpha facts with that id
  if node.idName != "":
    let id = vars[node.idName].type0
    if node.alphaNode.facts.hasKey(id):
      for alphaFact in node.alphaNode.facts[id].values:
        var newVars = vars
        if getVarsFromFact(newVars, node.condition, alphaFact):
          var newIdAttrs = idAttrs
          newIdAttrs.add(alphaFact.getIdAttr)
          var newToken = token
          newToken.fact = alphaFact
          session.leftActivation(node.child, newIdAttrs, newVars, newToken, false)
  else:
    for factsForId in node.alphaNode.facts.values:
      for alphaFact in factsForId.values:
        var newVars = vars
        if getVarsFromFact(newVars, node.condition, alphaFact):
          var newIdAttrs = idAttrs
          newIdAttrs.add(alphaFact.getIdAttr)
          var newToken = token
          newToken.fact = alphaFact
          session.leftActivation(node.child, newIdAttrs, newVars, newToken, false)

proc leftActivation[T](session: var Session[T], node: var MemoryNode[T], idAttrs: IdAttrs, vars: Vars[T], token: Token[T], fromAlpha: bool) =
  if fromAlpha and (token.kind == Insert or token.kind == Update) and node.condition.shouldTrigger:
    node.leafNode.trigger = true

  case token.kind:
  of Insert, Update:
    let enabled = node.nodeType != Leaf or node.filter == nil or node.filter(vars)
    let trigger = node.nodeType == Leaf and node.trigger and enabled
    node.lastMatchId += 1
    node.matchIds[node.lastMatchId] = idAttrs
    node.matches[idAttrs] = Match[T](id: node.lastMatchId, vars: vars, enabled: enabled, trigger: trigger)
    if node.nodeType == Leaf and node.callback != nil and trigger:
      session.thenNodes[].incl(node.addr)
  of Retract:
    node.matchIds.del(node.matches[idAttrs].id)
    node.matches.del(idAttrs)

  if node.nodeType != Leaf:
    session.leftActivation(node.child, idAttrs, vars, token)

proc rightActivation[T](session: var Session[T], node: JoinNode[T], idAttr: IdAttr, token: Token[T]) =
  if node.parent == nil: # root node
    var vars = Vars[T]()
    if getVarsFromFact(vars, node.condition, token.fact):
      session.leftActivation(node.child, @[idAttr], vars, token, true)
  else:
    for idAttrs, match in node.parent.matches.pairs:
      let vars = match.vars
      # SHORTCUT: if we know the id, compare it with the token right away
      if node.idName != "" and vars[node.idName].type0 != token.fact.id.type0:
        continue
      var newVars = vars # making a mutable copy here is far faster than making `vars` mutable above
      var newIdAttrs = idAttrs
      newIdAttrs.add(idAttr)
      if getVarsFromFact(newVars, node.condition, token.fact):
        session.leftActivation(node.child, newIdAttrs, newVars, token, true)

proc rightActivation[T](session: var Session[T], node: var AlphaNode[T], token: Token[T]) =
  let idAttr = token.fact.getIdAttr
  case token.kind:
  of Insert:
    if not node.facts.hasKey(idAttr.id):
      node.facts[idAttr.id] = initTable[int, Fact[T]]()
    node.facts[idAttr.id][idAttr.attr] = token.fact
    if not session.idAttrNodes.hasKey(idAttr):
      session.idAttrNodes[idAttr] = initHashSet[ptr AlphaNode[T]](initialSize = 4)
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
    session.rightActivation(child, idAttr, token)

proc fireRules*[T](session: var Session[T]) =
  # find all nodes with `then` blocks that need executed
  var thenNodes: seq[ptr MemoryNode[T]]
  for node in session.thenNodes[].items:
    thenNodes.add(node)
  if thenNodes.len == 0:
    return
  session.thenNodes[].clear
  # collect all nodes/vars to be executed
  var thenQueue: seq[(MemoryNode[T], Vars[T])]
  for node in thenNodes:
    node.trigger = false
    for match in node.matches.values:
      if match.trigger:
        thenQueue.add((node: node[], vars: match.vars))
  # execute `then` blocks
  for (node, vars) in thenQueue:
    node.callback(vars)
  # recur because there may be new `then` blocks to execute
  session.fireRules()

proc getAlphaNodesForFact[T](session: var Session[T], node: var AlphaNode[T], fact: Fact[T], root: bool, nodes: var HashSet[ptr AlphaNode[T]]) =
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

proc upsertFact[T](session: var Session[T], fact: Fact[T], nodes: HashSet[ptr AlphaNode[T]]) =
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

proc insertFact*[T](session: var Session[T], fact: Fact[T]) =
  var nodes = initHashSet[ptr AlphaNode[T]](initialSize = 4)
  getAlphaNodesForFact(session, session.alphaNode, fact, true, nodes)
  session.upsertFact(fact, nodes)
  if session.autoFire and not session.insideRule:
    session.fireRules()

proc retractFact*[T](session: var Session[T], fact: Fact[T]) =
  let idAttr = fact.getIdAttr
  # we use toSeq here to make a copy of idAttrNodes[idAttr], since
  # rightActivation will modify it
  for node in session.idAttrNodes[idAttr].items.toSeq:
    assert fact == node.facts[idAttr.id][idAttr.attr]
    session.rightActivation(node[], Token[T](fact: fact, kind: Retract))

proc retractFact*[T](session: var Session[T], id: T, attr: T) =
  let id = id.type0
  let attr = attr.type1.ord
  let idAttr = (id, attr)
  # we use toSeq here to make a copy of idAttrNodes[idAttr], since
  # rightActivation will modify it
  for node in session.idAttrNodes[idAttr].items.toSeq:
    let fact = node.facts[id][attr]
    session.rightActivation(node[], Token[T](fact: fact, kind: Retract))

proc initSession*[T](autoFire: bool = true): Session[T] =
  result.alphaNode = new(AlphaNode[T])
  result.leafNodes = newTable[string, MemoryNode[T]]()
  result.idAttrNodes = newTable[IdAttr, HashSet[ptr AlphaNode[T]]]()
  new result.thenNodes
  result.thenNodes[] = initHashSet[ptr MemoryNode[T]]()
  result.autoFire = autoFire

proc initProduction*[T, U](name: string, cb: SessionCallbackFn[T], query: QueryFn[T, U], filter: FilterFn[T]): Production[T, U] =
  result.name = name
  result.callback = cb
  result.query = query
  result.filter = filter

proc matchesParams[I, T](vars: Vars[T], params: array[I, (string, T)]): bool =
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

proc get*[T, U](session: Session[T], prod: Production[T, U], i: int): U =
  let idAttrs = session.leafNodes[prod.name].matchIds[i]
  prod.query(session.leafNodes[prod.name].matches[idAttrs].vars)
