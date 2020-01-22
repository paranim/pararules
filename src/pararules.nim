import strformat, tables, algorithm

type
  # facts
  Field = enum
    Identifier, Attribute, Value
  Fact[T] = tuple[id: T, attr: T, value: T]
  Token[T] = tuple[fact: Fact[T], insert: bool]
  IdAttr = tuple[id: int, attr: int]
  # alpha network
  AlphaNode[T] = ref object
    testField: Field
    testValue: T
    facts: Table[IdAttr, Fact[T]]
    successors: seq[JoinNode[T]]
    children: seq[AlphaNode[T]]
  # beta network
  TestAtJoinNode = object
    alphaField: Field
    betaField: Field
    condition: int
  NodeType = enum
    Root, Partial, Full
  MemoryNode[T] = ref object
    parent: JoinNode[T]
    children: seq[JoinNode[T]]
    facts*: seq[seq[Fact[T]]]
    factIndex: Table[IdAttr, int]
    case nodeType: NodeType
    of Full:
      production: Production[T]
    else:
      nil
  JoinNode[T] = ref object
    parent: MemoryNode[T]
    children: seq[MemoryNode[T]]
    alphaNode: AlphaNode[T]
    tests: seq[TestAtJoinNode]
  # session
  Vars[T] = Table[string, T]
  Var* = object
    name*: string
    field: Field
  Condition[T] = object
    nodes: seq[AlphaNode[T]]
    vars: seq[Var]
  Production[T] = object
    conditions: seq[Condition[T]]
    callback: proc (vars: Vars[T])
  Session[T] = object
    alphaNode: AlphaNode[T]
    betaNode: MemoryNode[T]
    allFacts: Table[IdAttr, Fact[T]]

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

proc addCondition*[T](production: var Production[T], id: Var or T, attr: Var or T, value: Var or T) =
  var condition = Condition[T]()
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
        when attr is T:
          condition.nodes.add AlphaNode[T](testField: fieldType, testValue: attr)
        else:
          var temp = attr
          temp.field = fieldType
          condition.vars.add(temp)
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

proc addProduction*[T](session: Session[T], production: Production[T]): MemoryNode[T] =
  var joins: Table[string, (Var, int)]
  result = session.betaNode
  let last = production.conditions.len - 1
  for i in 0 .. last:
    var condition = production.conditions[i]
    var leafNode = session.addNodes(condition.nodes)
    var joinNode = JoinNode[T](parent: result, alphaNode: leafNode)
    for v in condition.vars:
      if joins.hasKey(v.name):
        let (joinVar, condNum) = joins[v.name]
        joinNode.tests.add(TestAtJoinNode(alphaField: v.field, betaField: joinVar.field, condition: condNum))
      joins[v.name] = (v, i)
    result.children.add(joinNode)
    leafNode.successors.add(joinNode)
    # successors must be sorted by ancestry (descendents first) to avoid duplicate rule firings
    leafNode.successors.sort(proc (x, y: JoinNode[T]): int =
      if isAncestor(x, y): 1 else: -1)
    var newMemNode = MemoryNode[T](parent: joinNode, nodeType: if i == last: Full else: Partial)
    if newMemNode.nodeType == Full:
      newMemNode.production = production
    joinNode.children.add(newMemNode)
    result = newMemNode

proc performJoinTest(test: TestAtJoinNode, alphaFact: Fact, betaFact: Fact): bool =
  let arg1 = case test.alphaField:
    of Field.Identifier: alphaFact[0]
    of Field.Attribute: alphaFact[1]
    of Field.Value: alphaFact[2]
  let arg2 = case test.betaField:
    of Field.Identifier: betaFact[0]
    of Field.Attribute: betaFact[1]
    of Field.Value: betaFact[2]
  arg1 == arg2

proc performJoinTests(tests: seq[TestAtJoinNode], facts: seq[Fact], alphaFact: Fact): bool =
  for test in tests:
    let betaFact = facts[test.condition]
    if not performJoinTest(test, alphaFact, betaFact):
      return false
  true

proc leftActivation[T](node: MemoryNode[T], facts: seq[Fact[T]], token: Token[T])

proc leftActivation[T](node: JoinNode[T], facts: seq[Fact[T]], insert: bool) =
  for alphaFact in node.alphaNode.facts.values:
    if performJoinTests(node.tests, facts, alphaFact):
      for child in node.children:
        child.leftActivation(facts, (alphaFact, insert))

proc leftActivation[T](node: MemoryNode[T], facts: seq[Fact[T]], token: Token[T]) =
  var newFacts = facts
  newFacts.add(token.fact)

  let id = token.fact.id.idVal.ord
  let attr = token.fact.attr.attrVal.ord
  let idAttr = (id, attr)
  if token.insert:
    let index = node.facts.len
    node.facts.add(newFacts)
    node.factIndex[idAttr] = index
  else:
    let index = node.factIndex[idAttr]
    node.facts.delete(index)
    node.factIndex.del(idAttr)

  if node.nodeType == Full:
    assert node.production.conditions.len == newFacts.len
    var vars: Vars[T]
    for i in 0 ..< node.production.conditions.len:
      for v in node.production.conditions[i].vars:
        case v.field:
          of Identifier:
            if vars.hasKey(v.name):
              assert vars[v.name] == newFacts[i][0]
            else:
              vars[v.name] = newFacts[i][0]
          of Attribute:
            if vars.hasKey(v.name):
              assert vars[v.name] == newFacts[i][1]
            else:
              vars[v.name] = newFacts[i][1]
          of Value:
            if vars.hasKey(v.name):
              assert vars[v.name] == newFacts[i][2]
            else:
              vars[v.name] = newFacts[i][2]
    node.production.callback(vars)
  else:
    for child in node.children:
      child.leftActivation(newFacts, token.insert)

proc rightActivation[T](node: JoinNode[T], token: Token[T]) =
  if node.parent.nodeType == Root:
    for child in node.children:
      child.leftActivation(@[], token)
  else:
    for facts in node.parent.facts:
      if performJoinTests(node.tests, facts, token.fact):
        for child in node.children:
          child.leftActivation(facts, token)

proc rightActivation[T](node: AlphaNode[T], token: Token[T]) =
  let id = token.fact.id.idVal.ord
  let attr = token.fact.attr.attrVal.ord
  if token.insert:
    node.facts[(id, attr)] = token.fact
  else:
    node.facts.del((id, attr))
  for child in node.successors:
    child.rightActivation(token)

proc addFact(node: AlphaNode, fact: Fact, root: bool, insert: bool): bool =
  if not root:
    let val = case node.testField:
      of Field.Identifier: fact[0]
      of Field.Attribute: fact[1]
      of Field.Value: fact[2]
    if val != node.testValue:
      return false
  for child in node.children:
    if child.addFact(fact, false, insert):
      return true
  node.rightActivation((fact, insert))
  true

proc addFact*[T](session: var Session[T], fact: Fact[T]) =
  let id = fact.id.idVal.ord
  let attr = fact.attr.attrVal.ord
  let idAttr = (id, attr)
  if session.allFacts.hasKey(idAttr):
    session.removeFact(session.allFacts[idAttr])
  session.allFacts[idAttr] = fact
  discard session.alphaNode.addFact(fact, true, true)

proc removeFact*[T](session: Session[T], fact: Fact[T]) =
  discard session.alphaNode.addFact(fact, true, false)

proc newSession*[T](): Session[T] =
  result.alphaNode = new(AlphaNode[T])
  result.betaNode = new(MemoryNode[T])

proc newProduction*[T](cb: proc (vars: Vars[T])): Production[T] =
  result.callback = cb

proc print(fact: Fact, indent: int): string
proc print[T](node: JoinNode[T], indent: int): string
proc print[T](node: MemoryNode[T], indent: int): string
proc print(node: AlphaNode, indent: int): string

proc print(fact: Fact, indent: int): string =
  if indent >= 0:
    for i in 0 ..< indent:
      result &= "  "
  result &= "Fact = {fact} \n".fmt

proc print[T](node: JoinNode[T], indent: int): string =
  for i in 0 ..< indent:
    result &= "  "
  result &= "JoinNode\n"
  for child in node.children:
    result &= print(child, indent+1)

proc print[T](node: MemoryNode[T], indent: int): string =
  for i in 0 ..< indent:
    result &= "  "
  let cnt = node.facts.len
  if node.nodeType == Full:
    result &= "ProdNode ({cnt})\n".fmt
  else:
    result &= "MemoryNode ({cnt})\n".fmt
  for child in node.children:
    result &= print(child, indent+1)

proc print(node: AlphaNode, indent: int): string =
  let cnt = node.successors.len
  if indent == 0:
    result &= "AlphaNode ({cnt})\n".fmt
  else:
    for i in 0 ..< indent:
      result &= "  "
    result &= "{node.testField} = {node.testValue} ({cnt})\n".fmt
  for fact in node.facts:
    result &= print(fact, indent+1)
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  var alphaNode = session.alphaNode
  print(alphaNode, 0) & print(session.betaNode, 0)
