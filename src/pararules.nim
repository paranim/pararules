import strformat

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
  TestAtJoinNode = object
    alphaField: Field
    betaField: Field
  BetaNode[T] = ref object of RootObj
    children: seq[BetaNode[T]]
    parent: BetaNode[T]
  MemoryNode[T] = ref object of BetaNode[T]
    facts: seq[Fact[T]]
  JoinNode[T] = ref object of BetaNode[T]
    alphaNode: AlphaNode[T]
    tests: seq[TestAtJoinNode]
  ProdNode[T] = ref object of BetaNode[T]
  # session
  Var* = object
    name*: string
  Production[T] = object
    nodes: seq[AlphaNode[T]]
  Session[T] = object
    alphaNode: AlphaNode[T]
    betaNode: BetaNode[T]

proc addNode(node: var AlphaNode, newNode: AlphaNode) =
  for child in node.children.mitems():
    if child.testField == newNode.testField and child.testValue == newNode.testValue:
      for newChild in newNode.children:
        child.addNode(newChild)
      return
  node.children.add(newNode)

proc addNode(session: var Session, newNode: AlphaNode) =
  session.alphaNode.addNode(newNode)

proc addCondition*[T](production: var Production[T], id: Var or T, attr: Var or T, value: Var or T) =
  var node: AlphaNode[T] = nil
  for fieldType in [Field.Value, Field.Attribute, Field.Identifier]:
    var newNode: AlphaNode[T] = nil
    case fieldType:
      of Field.None:
        continue
      of Field.Value:
        when value is T:
          newNode = AlphaNode[T](testField: fieldType, testValue: value)
      of Field.Attribute:
        when attr is T:
          newNode = AlphaNode[T](testField: fieldType, testValue: attr)
      of Field.Identifier:
        when id is T:
          newNode = AlphaNode[T](testField: fieldType, testValue: id)
    if newNode != nil:
      if node != nil:
        newNode.children.add(node)
      node = newNode
  if node != nil:
    production.nodes.add(node)

proc addProduction*[T](session: var Session[T], production: Production[T]) =
  for node in production.nodes:
    session.addNode(node)

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
