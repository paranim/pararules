import strformat

type
  # alpha network
  Field* {.pure.} = enum
    None, Identifier, Attribute, Value
  Fact*[T] = tuple[id: T, attr: T, value: T]
  AlphaNode*[T] = ref object
    testField*: Field
    testValue*: T
    facts*: seq[Fact[T]]
    successors*: seq[BetaNode[T]]
    children*: seq[AlphaNode[T]]
  # beta network
  Token*[T] = ref object
    parent: Token[T]
    fact: Fact[T]
  TestAtJoinNode = object
    fieldOfArg1: Field
    conditionNumberOfArg2: int
    fieldOfArg2: Field
  BetaType* {.pure.} = enum
    Memory, Join, Prod
  BetaNode*[T] = ref object
    children: seq[BetaNode[T]]
    parent: BetaNode[T]
    case kind*: BetaType
    of Memory:
      tokens: seq[Token[T]]
    of Join:
      alphaNode: AlphaNode[T]
      tests: seq[TestAtJoinNode]
    of Prod:
      nil
  # session
  Session*[T] = object
    rootNode*: AlphaNode[T]

proc addNode(node: var AlphaNode, newNode: AlphaNode) =
  for child in node.children.mitems():
    if child.testField == newNode.testField and child.testValue == newNode.testValue:
      for newChild in newNode.children:
        child.addNode(newChild)
      return
  node.children.add(newNode)

proc addNode*(session: var Session, newNode: AlphaNode) =
  session.rootNode.addNode(newNode)

proc rightActivation(node: BetaNode, fact: Fact) =
  echo fact

proc leftActivation(node: BetaNode, token: Token) =
  echo token

proc alphaMemoryRightActivation(node: var AlphaNode, fact: Fact) =
  node.facts.add(fact)
  for child in node.successors.mitems():
    child.rightActivation(fact)

proc betaMemoryLeftActivation(node: BetaNode, token: Token, fact: Fact) =
  let newToken = new(Token)
  newToken.parent = token
  newToken.fact = fact
  node.tokens.add(newToken)
  for child in node.children.mitems():
    child.leftActivation()

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
  session.rootNode.addFact(fact)

proc print(fact: Fact, indent: int): string =
  if indent >= 0:
    for i in 0..indent-1:
      result &= "  "
  result &= "Fact = {fact} \n".fmt

proc print(node: AlphaNode, indent: int): string =
  if indent >= 0:
    for i in 0..indent-1:
      result &= "  "
    result &= "{node.testField} = {node.testValue}\n".fmt
  for fact in node.facts:
    result &= print(fact, indent+1)
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  print(session.rootNode, -1)
