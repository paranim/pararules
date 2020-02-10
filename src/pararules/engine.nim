import strformat, tables, algorithm

type
  # facts
  Field* = enum
    Identifier, Attribute, Value
  Fact[T] = tuple[id: T, attr: T, value: T]
  Token[T] = tuple[fact: Fact[T], insert: bool, originalFact: Fact[T]]
  IdAttr = tuple[id: int, attr: int]
  Vars[T] = Table[string, T]
  Var* = object
    name*: string
    field: Field
  CallbackFn[T] = proc (vars: Vars[T])
  SessionCallbackFn[T] = proc (session: var Session[T], vars: Vars[T])
  QueryFn[T, U] = proc (vars: Vars[T]): U
  FilterFn[T] = proc (vars: Vars[T]): bool
  Queue[T] = ref seq[tuple[callback: CallbackFn[T], vars: Vars[T]]]
  # alpha network
  AlphaNode[T] = ref object
    testField: Field
    testValue: T
    facts: Table[IdAttr, Fact[T]]
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
    prodNode: MemoryNode[T]
    case nodeType: MemoryNodeType
      of Prod:
        callback: CallbackFn[T]
        trigger: bool
        queue: Queue[T]
      else:
        nil
    when not defined(release):
      debugFacts*: seq[seq[Fact[T]]]
  JoinNode[T] = ref object
    parent: MemoryNode[T]
    children: seq[MemoryNode[T]]
    alphaNode: AlphaNode[T]
    condition: Condition[T]
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
    idAttrNodes: ref Table[IdAttr, seq[AlphaNode[T]]]
    insideRule*: bool
    queue: Queue[T]

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
  var memNodes: seq[MemoryNode[T]]
  let last = production.conditions.len - 1
  for i in 0 .. last:
    var condition = production.conditions[i]
    var leafNode = session.addNodes(condition.nodes)
    var joinNode = JoinNode[T](parent: memNode, alphaNode: leafNode, condition: condition)
    memNode.children.add(joinNode)
    leafNode.successors.add(joinNode)
    # successors must be sorted by ancestry (descendents first) to avoid duplicate rule firings
    leafNode.successors.sort(proc (x, y: JoinNode[T]): int =
      if isAncestor(x, y): 1 else: -1)
    var newMemNode = MemoryNode[T](parent: joinNode, nodeType: if i == last: Prod else: Partial, condition: condition)
    if newMemNode.nodeType == Prod:
      var sess = session
      newMemNode.callback = proc (vars: Vars[T]) = production.callback(sess, vars)
      newMemNode.queue = session.queue
      if session.prodNodes.hasKey(production.name):
        raise newException(Exception, production.name & " already exists in session")
      session.prodNodes[production.name] = newMemNode
    memNodes.add(newMemNode)
    joinNode.children.add(newMemNode)
    memNode = newMemNode
  for node in memNodes:
    node.prodNode = memNode

proc getVarsFromFact[T](vars: var Vars[T], condition: Condition[T], fact: Fact[T]): bool =
  for v in condition.vars:
    case v.field:
      of Identifier:
        if vars.hasKey(v.name) and vars[v.name] != fact[0]:
          return false
        else:
          vars[v.name] = fact[0]
      of Attribute:
        if vars.hasKey(v.name) and vars[v.name] != fact[1]:
          return false
        else:
          vars[v.name] = fact[1]
      of Value:
        if vars.hasKey(v.name) and vars[v.name] != fact[2]:
          return false
        else:
          vars[v.name] = fact[2]
  true

proc performJoinTests(node: JoinNode, vars: Vars, alphaFact: Fact): bool =
  var newVars = vars
  if not newVars.getVarsFromFact(node.condition, alphaFact):
    return false
  if node.condition.filter != nil:
    if not node.condition.filter(newVars):
      return false
  true

proc leftActivation[T](node: MemoryNode[T], vars: Vars[T], debugFacts: seq[Fact[T]], token: Token[T])

proc leftActivation[T](node: JoinNode[T], vars: Vars[T], debugFacts: seq[Fact[T]], token: Token[T]) =
  for alphaFact in node.alphaNode.facts.values:
    if performJoinTests(node, vars, alphaFact):
      for child in node.children:
        child.leftActivation(vars, debugFacts, (alphaFact, token.insert, token.originalFact))

proc leftActivation[T](node: MemoryNode[T], vars: Vars[T], debugFacts: seq[Fact[T]], token: Token[T]) =
  var newVars = vars
  let success = newVars.getVarsFromFact(node.condition, token.fact)
  assert success

  when not defined(release):
    var debugFacts = debugFacts
    debugFacts.add(token.fact)

  if token.insert:
    node.vars.add(newVars)
    when not defined(release):
      node.debugFacts.add(debugFacts)
  else:
    let index = node.vars.find(newVars)
    assert index >= 0
    node.vars.delete(index)
    when not defined(release):
      node.debugFacts.delete(index)

  if token.insert and node.condition.shouldTrigger and token.fact == token.originalFact:
    node.prodNode.trigger = true

  if node.nodeType == Prod and token.insert and node.trigger:
    node.trigger = false
    node.queue[].add((callback: node.callback, vars: newVars))
  else:
    for child in node.children:
      child.leftActivation(newVars, debugFacts, token)

proc rightActivation[T](node: JoinNode[T], token: Token[T]) =
  if node.parent.nodeType == Root:
    if performJoinTests(node, Vars[T](), token.fact):
      for child in node.children:
        child.leftActivation(initTable[string, T](), newSeq[Fact[T]](), token)
  else:
    for i in 0 ..< node.parent.vars.len:
      let vars = node.parent.vars[i]
      let debugFacts =
        when not defined(release):
          node.parent.debugFacts[i]
        else:
          newSeq[Fact[T]]()
      if performJoinTests(node, vars, token.fact):
        for child in node.children:
          child.leftActivation(vars, debugFacts, token)

proc rightActivation[T](session: Session[T], node: AlphaNode[T], token: Token[T]) =
  let id = token.fact.id.type0.ord
  let attr = token.fact.attr.type1.ord
  let idAttr = (id, attr)
  if token.insert:
    node.facts[idAttr] = token.fact
    if session.idAttrNodes.hasKey(idAttr):
      session.idAttrNodes[idAttr].add(node)
    else:
      session.idAttrNodes[idAttr] = @[node]
  else:
    node.facts.del(idAttr)
  for child in node.successors:
    child.rightActivation(token)

proc updateFact(session: Session, node: AlphaNode, fact: Fact, root: bool, insert: bool) =
  if not root:
    let val = case node.testField:
      of Field.Identifier: fact[0]
      of Field.Attribute: fact[1]
      of Field.Value: fact[2]
    if val != node.testValue:
      return
  for child in node.children:
    session.updateFact(child, fact, false, insert)
  session.rightActivation(node, (fact, insert, fact))

proc insertFact*[T](session: Session[T], fact: Fact[T])
proc removeFact*[T](session: Session[T], fact: Fact[T])

proc emptyQueue[T](session: Session[T]) =
  while true:
    let queue = session.queue[]
    if queue.len == 0:
      break
    session.queue[] = @[]
    for (callback, vars) in queue:
      callback(vars)

proc insertFact*[T](session: Session[T], fact: Fact[T]) =
  let id = fact.id.type0.ord
  let attr = fact.attr.type1.ord
  let idAttr = (id, attr)
  if session.idAttrNodes.hasKey(idAttr):
    for node in session.idAttrNodes[idAttr]:
      let oldFact = node.facts[idAttr]
      session.rightActivation(node, (oldFact, false, oldFact))
    session.idAttrNodes.del(idAttr)
  session.updateFact(session.alphaNode, fact, true, true)
  if not session.insideRule:
    session.emptyQueue()

proc removeFact*[T](session: Session[T], fact: Fact[T]) =
  session.updateFact(session.alphaNode, fact, true, false)

proc initSession*[T](): Session[T] =
  result.alphaNode = new(AlphaNode[T])
  result.betaNode = new(MemoryNode[T])
  result.prodNodes = newTable[string, MemoryNode[T]]()
  result.idAttrNodes = newTable[IdAttr, seq[AlphaNode[T]]]()
  new result.queue

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
