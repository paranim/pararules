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
    successors: Table[ptr MemoryNode[T], JoinNode[T]]
    children: seq[AlphaNode[T]]
  # beta network
  TestAtJoinNode = object
    alphaField: Field
    betaField: Field
  Token[T] = object
    alphaNode: AlphaNode[T]
    fact: Fact[T]
  BetaNode[T] = ref object of RootObj
    children: seq[BetaNode[T]]
    parent: BetaNode[T]
  MemoryNode[T] = ref object of BetaNode[T]
    tokens: seq[Token[T]]
  JoinNode[T] = ref object of BetaNode[T]
    alphaNode: AlphaNode[T]
    tests: seq[TestAtJoinNode]
  ProdNode[T] = ref object of BetaNode[T]
  # session
  Var* = object
    name*: string
  Production[T] = object
    conditions: seq[seq[AlphaNode[T]]]
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
  var condition: seq[AlphaNode[T]]
  for fieldType in [Field.Identifier, Field.Attribute, Field.Value]:
    case fieldType:
      of Field.None:
        continue
      of Field.Identifier:
        when id is T:
          condition.add AlphaNode[T](testField: fieldType, testValue: id)
      of Field.Attribute:
        when attr is T:
          condition.add AlphaNode[T](testField: fieldType, testValue: attr)
      of Field.Value:
        when value is T:
          condition.add AlphaNode[T](testField: fieldType, testValue: value)
  if condition.len > 0:
    production.conditions.add(condition)

proc addProduction*[T](session: var Session[T], production: Production[T]) =
  for condition in production.conditions:
    var leafNode = session.addNodes(condition)
    var betaNode = session.betaNode
    if not leafNode.successors.hasKey(betaNode.addr):
      var joinNode = JoinNode[T](parent: betaNode, alphaNode: leafNode)
      leafNode.successors[betaNode.addr] = joinNode
      betaNode.children.add(joinNode)

proc rightActivation(node: var JoinNode, fact: Fact) =
  echo fact

proc alphaMemoryRightActivation(node: var AlphaNode, fact: Fact) =
  node.facts.add(fact)
  for child in node.successors.mvalues():
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

proc print(fact: Fact, indent: int): string =
  if indent >= 0:
    for i in 0 ..< indent:
      result &= "  "
  result &= "Fact = {fact} \n".fmt

proc print(node: AlphaNode, indent: int): string =
  if indent >= 0:
    for i in 0 ..< indent:
      result &= "  "
    result &= "{node.testField} = {node.testValue}\n".fmt
  for fact in node.facts:
    result &= print(fact, indent+1)
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  print(session.alphaNode, -1)
