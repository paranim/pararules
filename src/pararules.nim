import strformat, tables

type
  # alpha network
  Field = enum
    None, Identifier, Attribute, Value
  Fact[T] = tuple[id: T, attr: T, value: T]
  AlphaNode[T] = ref object
    testField: Field
    testValue: T
    facts: seq[Fact[T]]
    successors: seq[JoinNode[T]]
    children: seq[AlphaNode[T]]
  # beta network
  TestAtJoinNode[T] = object
    alphaField: Field
    betaField: Field
    originNode: AlphaNode[T]
  Token[T] = object
    originNode: AlphaNode[T]
    fact: Fact[T]
  MemoryNode[T] = ref object
    parent: JoinNode[T]
    children: seq[JoinNode[T]]
    tokens: seq[Token[T]]
    prod: bool
  JoinNode[T] = ref object
    parent: MemoryNode[T]
    children: seq[MemoryNode[T]]
    alphaNode: AlphaNode[T]
    tests: seq[TestAtJoinNode[T]]
  # session
  Var* = object
    name*: string
    field: Field
  Condition[T] = object
    nodes: seq[AlphaNode[T]]
    vars: seq[Var]
  Production[T] = object
    conditions: seq[Condition[T]]
  Session[T] = object
    alphaNode: AlphaNode[T]
    betaNode: MemoryNode[T]

proc addNode(node: var AlphaNode, newNode: AlphaNode): AlphaNode =
  for child in node.children:
    if child.testField == newNode.testField and child.testValue == newNode.testValue:
      return child
  node.children.add(newNode)
  return newNode

proc addNodes(session: var Session, nodes: seq[AlphaNode]): AlphaNode =
  result = session.alphaNode
  for node in nodes:
    result = result.addNode(node)

proc addCondition*[T](production: var Production[T], id: Var or T, attr: Var or T, value: Var or T) =
  var condition = Condition[T]()
  for fieldType in [Field.Identifier, Field.Attribute, Field.Value]:
    case fieldType:
      of Field.None:
        continue
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

proc addProduction*[T](session: var Session[T], production: Production[T]) =
  var joins: Table[string, (Var, AlphaNode[T])]
  var memNode = session.betaNode
  let last = production.conditions.len - 1
  for i in 0 .. last:
    var condition = production.conditions[i]
    var leafNode = session.addNodes(condition.nodes)
    var joinNode = JoinNode[T](parent: memNode, alphaNode: leafNode)
    for v in condition.vars:
      if joins.hasKey(v.name):
        let (joinVar, joinAlphaNode) = joins[v.name]
        joinNode.tests.add(TestAtJoinNode[T](alphaField: v.field, betaField: joinVar.field, originNode: joinAlphaNode))
      joins[v.name] = (v, leafNode)
    memNode.children.add(joinNode)
    leafNode.successors.add(joinNode)
    var newMemNode = MemoryNode[T](parent: joinNode, prod: i == last)
    joinNode.children.add(newMemNode)
    memNode = newMemNode

proc rightActivation(node: var JoinNode, fact: Fact) =
  echo fact

proc alphaMemoryRightActivation(node: var AlphaNode, fact: Fact) =
  node.facts.add(fact)
  for child in node.successors.mitems():
    child.rightActivation(fact)

proc addFact(node: var AlphaNode, fact: Fact) =
  let val = case node.testField:
    of Field.None: node.testValue
    of Field.Identifier: fact[0]
    of Field.Attribute: fact[1]
    of Field.Value: fact[2]
  if val != node.testValue:
    return
  elif node.testField != Field.None:
    node.alphaMemoryRightActivation(fact)
  for child in node.children.mitems():
    child.addFact(fact)

proc addFact*(session: var Session, fact: Fact) =
  session.alphaNode.addFact(fact)

proc newSession*[T](): Session[T] =
  result.alphaNode = new(AlphaNode[T])
  result.betaNode = new(MemoryNode[T])

proc newProduction*[T](): Production[T] =
  result

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
  if node.prod:
    result &= "ProdNode\n"
  else:
    result &= "MemoryNode\n"
  for child in node.children:
    result &= print(child, indent+1)

proc print(node: AlphaNode, indent: int): string =
  if indent == 0:
    result &= "AlphaNode\n"
  else:
    for i in 0 ..< indent:
      result &= "  "
    result &= "{node.testField} = {node.testValue}\n".fmt
  for fact in node.facts:
    result &= print(fact, indent+1)
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  print(session.alphaNode, 0) & print(session.betaNode, 0)
