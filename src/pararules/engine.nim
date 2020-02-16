import strformat, tables, algorithm, sets

type
  # facts
  Field* = enum
    Identifier, Attribute, Value
  Fact[T] = tuple[id: T, attr: T, value: T]
  Token[T] = tuple[fact: Fact[T], insert: bool]
  IdAttr = tuple[id: int, attr: int]

  # vars
  Vars[T] = Table[string, T]
  Var* = object
    name*: string
    field: Field

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
    Root, Partial, Prod
  MemoryNode[T] = ref object
    parent: JoinNode[T]
    children: seq[JoinNode[T]]
    vars*: seq[Vars[T]]
    condition: Condition[T]
    case nodeType: MemoryNodeType
      of Prod:
        callback: CallbackFn[T]
        trigger: bool
      else:
        nil
    when not defined(release):
      debugFacts*: seq[seq[Fact[T]]]
  JoinNode[T] = ref object
    parent: MemoryNode[T]
    children: seq[MemoryNode[T]]
    alphaNode: AlphaNode[T]
    condition: Condition[T]
    prodNode: MemoryNode[T]
    idName: string

  # session
  Condition[T] = object
    nodes: seq[AlphaNode[T]]
    vars: seq[Var]
    filter: FilterFn[T]
    shouldTrigger: bool
  Production*[T, U] = object
    callback: SessionCallbackFn[T]
    conditions: seq[Condition[T]]
    query: QueryFn[T, U]
    name: string
  Session*[T] = object
    alphaNode: AlphaNode[T]
    betaNode: MemoryNode[T]
    prodNodes*: ref Table[string, MemoryNode[T]]
    idAttrNodes: ref Table[IdAttr, HashSet[ptr AlphaNode[T]]]
    insideRule*: bool
    thenQueue: ref seq[tuple[node: MemoryNode[T], vars: Vars[T]]]

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

proc add*[T, U](production: var Production[T, U], id: Var or T, attr: T, value: Var or T, filter: FilterFn[T], then: bool) =
  var condition = Condition[T](filter: filter, shouldTrigger: then)
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
  var memNode = session.betaNode
  var joinNodes: seq[JoinNode[T]]
  let last = production.conditions.len - 1
  var tests: HashSet[string]
  for i in 0 .. last:
    var condition = production.conditions[i]
    var leafNode = session.addNodes(condition.nodes)
    var joinNode = JoinNode[T](parent: memNode, alphaNode: leafNode, condition: condition)
    for v in condition.vars:
      if tests.contains(v.name):
        if v.field == Identifier:
          joinNode.idName = v.name
      else:
        tests.incl(v.name)
    memNode.children.add(joinNode)
    leafNode.successors.add(joinNode)
    # successors must be sorted by ancestry (descendents first) to avoid duplicate rule firings
    leafNode.successors.sort(proc (x, y: JoinNode[T]): int =
      if isAncestor(x, y): 1 else: -1)
    var newMemNode = MemoryNode[T](parent: joinNode, nodeType: if i == last: Prod else: Partial, condition: condition)
    if newMemNode.nodeType == Prod:
      var sess = session
      newMemNode.callback = proc (vars: Vars[T]) = production.callback(sess, vars)
      if session.prodNodes.hasKey(production.name):
        raise newException(Exception, production.name & " already exists in session")
      session.prodNodes[production.name] = newMemNode
    joinNodes.add(joinNode)
    joinNode.children.add(newMemNode)
    memNode = newMemNode
  for node in joinNodes:
    node.prodNode = memNode

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

proc performJoinTests(node: JoinNode, vars: Vars, alphaFact: Fact, insert: bool): bool =
  var newVars = vars
  if not newVars.getVarsFromFact(node.condition, alphaFact):
    return false
  # only check the filter on insertion, so we can
  # be sure that old facts are removed successfully,
  # even if they technically don't satisfy the condition anymore
  if insert and node.condition.filter != nil:
    if not node.condition.filter(newVars):
      return false
  true

proc leftActivation[T](session: var Session[T], node: MemoryNode[T], vars: Vars[T], debugFacts: ref seq[Fact[T]], token: Token[T])

proc leftActivation[T](session: var Session[T], node: JoinNode[T], vars: Vars[T], debugFacts: ref seq[Fact[T]], token: Token[T]) =
  # SHORTCUT: if we know the id, only loop over alpha facts with that id
  if node.idName != "":
    let id = vars[node.idName].type0
    if node.alphaNode.facts.hasKey(id):
      for alphaFact in node.alphaNode.facts[id].values:
        if performJoinTests(node, vars, alphaFact, token.insert):
          var newToken = token
          newToken.fact = alphaFact
          for child in node.children:
            session.leftActivation(child, vars, debugFacts, newToken)
  else:
    for factsForId in node.alphaNode.facts.values:
      for alphaFact in factsForId.values:
        if performJoinTests(node, vars, alphaFact, token.insert):
          var newToken = token
          newToken.fact = alphaFact
          for child in node.children:
            session.leftActivation(child, vars, debugFacts, newToken)

proc leftActivation[T](session: var Session[T], node: MemoryNode[T], vars: Vars[T], debugFacts: ref seq[Fact[T]], token: Token[T]) =
  var newVars = vars
  let success = newVars.getVarsFromFact(node.condition, token.fact)
  assert success

  when not defined(release):
    debugFacts[].add(token.fact)

  if token.insert:
    node.vars.add(newVars)
    when not defined(release):
      node.debugFacts.add(debugFacts[])
  else:
    let index = node.vars.find(newVars)
    if index >= 0:
      node.vars.delete(index)
      when not defined(release):
        node.debugFacts.delete(index)

  if node.nodeType == Prod:
    if token.insert:
      if node.trigger:
        session.thenQueue[].add((node: node, vars: newVars))
    else:
      let index = session.thenQueue[].find((node: node, vars: newVars))
      if index >= 0:
        session.thenQueue[].delete(index)
  else:
    for child in node.children:
      session.leftActivation(child, newVars, debugFacts, token)

proc rightActivation[T](session: var Session[T], node: JoinNode[T], token: Token[T]) =
  if token.insert and node.condition.shouldTrigger:
    node.prodNode.trigger = true
  when not defined(release):
    proc newRefSeq[T](s: seq[T]): ref seq[T] =
      new(result)
      result[] = s
  if node.parent.nodeType == Root:
    let vars = Vars[T]()
    if performJoinTests(node, vars, token.fact, token.insert):
      for child in node.children:
        let debugFacts: ref seq[Fact[T]] =
          when not defined(release):
            newRefSeq(newSeq[Fact[T]]())
          else:
            nil
        session.leftActivation(child, vars, debugFacts, token)
  else:
    for i in 0 ..< node.parent.vars.len:
      let vars = node.parent.vars[i]
      # SHORTCUT: if we know the id, compare it with the token right away
      if node.idName != "" and vars[node.idName].type0 != token.fact.id.type0:
        continue
      if performJoinTests(node, vars, token.fact, token.insert):
        let debugFacts: ref seq[Fact[T]] =
          when not defined(release):
            newRefSeq(node.parent.debugFacts[i])
          else:
            nil
        for child in node.children:
          session.leftActivation(child, vars, debugFacts, token)

proc rightActivation[T](session: var Session[T], node: var AlphaNode[T], token: Token[T]) =
  let id = token.fact.id.type0
  let attr = token.fact.attr.type1.ord
  let idAttr = (id, attr)
  if token.insert:
    if not node.facts.hasKey(id):
      node.facts[id] = initTable[int, Fact[T]]()
    node.facts[id][attr] = token.fact
    if not session.idAttrNodes.hasKey(idAttr):
      session.idAttrNodes[idAttr] = initHashSet[ptr AlphaNode[T]]()
    let exists = session.idAttrNodes[idAttr].containsOrIncl(node.addr)
    assert not exists
  else:
    node.facts[id].del(attr)
    let missing = session.idAttrNodes[idAttr].missingOrExcl(node.addr)
    assert not missing
  for child in node.successors:
    session.rightActivation(child, token)

proc insertFact[T](session: var Session[T], node: var AlphaNode[T], fact: Fact[T], root: bool) =
  if not root:
    let val = case node.testField:
      of Field.Identifier: fact[0]
      of Field.Attribute: fact[1]
      of Field.Value: fact[2]
    if val != node.testValue:
      return
  for child in node.children.mitems:
    session.insertFact(child, fact, false)
  if not root:
    session.rightActivation(node, (fact: fact, insert: true))

proc removeIdAttr[T](session: var Session[T], id: T, attr: T) =
  let id = id.type0
  let attr = attr.type1.ord
  let idAttr = (id, attr)
  if session.idAttrNodes.hasKey(idAttr):
    # copy the set into a seq since rightActivation will be modifying the set
    var idAttrNodes: seq[ptr AlphaNode[T]]
    for node in session.idAttrNodes[idAttr].items:
      idAttrNodes.add(node)
    # right activate each node
    for node in idAttrNodes:
      let oldFact = node.facts[id][attr]
      session.rightActivation(node[], (fact: oldFact, insert: false))

proc triggerThenBlocks[T](session: var Session[T]) =
  let thenQueue = session.thenQueue[]
  if thenQueue.len == 0:
    return
  session.thenQueue[] = @[]
  for (node, vars) in thenQueue:
    node.trigger = false
    node.callback(vars)
  session.triggerThenBlocks()

proc insertFact*[T](session: var Session[T], fact: Fact[T]) =
  session.removeIdAttr(fact.id, fact.attr)
  session.insertFact(session.alphaNode, fact, true)
  if not session.insideRule:
    session.triggerThenBlocks()

proc removeFact*[T](session: var Session[T], fact: Fact[T]) =
  session.removeIdAttr(fact.id, fact.attr)

proc initSession*[T](): Session[T] =
  result.alphaNode = new(AlphaNode[T])
  result.betaNode = new(MemoryNode[T])
  result.prodNodes = newTable[string, MemoryNode[T]]()
  result.idAttrNodes = newTable[IdAttr, HashSet[ptr AlphaNode[T]]]()
  new result.thenQueue

proc initProduction*[T, U](name: string, cb: SessionCallbackFn[T], query: QueryFn[T, U]): Production[T, U] =
  result.name = name
  result.callback = cb
  result.query = query

proc matches[I, T](vars: Vars[T], params: array[I, (string, T)]): bool =
  for (varName, val) in params:
    if vars[varname] != val:
      return false
  true

proc findIndex*[I, T](session: Session, prod: Production, params: array[I, (string, T)]): int =
  let vars = session.prodNodes[prod.name].vars
  result = vars.len - 1
  while result >= 0:
    if matches(vars[result], params):
      break
    result = result - 1

proc findIndex*(session: Session, prod: Production): int =
  let vars = session.prodNodes[prod.name].vars
  result = vars.len - 1

proc findAllIndices*[I, T](session: Session, prod: Production, params: array[I, (string, T)]): seq[int] =
  let vars = session.prodNodes[prod.name].vars
  for i in 0 ..< vars.len:
    if matches(vars[i], params):
      result.add(i)

proc findAllIndices*(session: Session, prod: Production): seq[int] =
  let vars = session.prodNodes[prod.name].vars
  for i in 0 ..< vars.len:
    result.add(i)

proc get*[T, U](session: Session[T], prod: Production[T, U], i: int): U =
  prod.query(session.prodNodes[prod.name].vars[i])
