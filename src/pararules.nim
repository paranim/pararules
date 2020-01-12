import strformat

type
  # alpha network
  Field* {.pure.} = enum
    None, Identifier, Attribute, Value
  Element*[T] = tuple[id: T, attr: T, value: T]
  AlphaNode*[T] = ref object
    testField*: Field
    testValue*: T
    elements*: seq[Element[T]]
    successors*: seq[BetaNode[T]]
    children*: seq[AlphaNode[T]]
  # beta network
  Token*[T] = ref object
    parent: Token[T]
    element: Element[T]
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

proc rightActivation(node: BetaNode, element: Element) =
  echo element

proc leftActivation(node: BetaNode, token: Token) =
  echo token

proc alphaMemoryRightActivation(node: var AlphaNode, element: Element) =
  node.elements.add(element)
  for child in node.successors.mitems():
    child.rightActivation(element)

proc betaMemoryLeftActivation(node: BetaNode, token: Token, element: Element) =
  let newToken = new(Token)
  newToken.parent = token
  newToken.element = element
  node.tokens.add(newToken)
  for child in node.children.mitems():
    child.leftActivation()

proc addElement(node: var AlphaNode, element: Element) =
  let val = case node.testField:
            of Field.None: node.testValue
            of Field.Identifier: element[0]
            of Field.Attribute: element[1]
            of Field.Value: element[2]
  if val != node.testValue:
    return
  elif node.testField != Field.None:
    node.alphaMemoryRightActivation(element)
  for child in node.children.mitems():
    child.addElement(element)

proc addElement*(session: var Session, element: Element) =
  session.rootNode.addElement(element)

proc print(element: Element, indent: int): string =
  if indent >= 0:
    for i in 0..indent-1:
      result &= "  "
  result &= "Element = {element} \n".fmt

proc print(node: AlphaNode, indent: int): string =
  if indent >= 0:
    for i in 0..indent-1:
      result &= "  "
    result &= "{node.testField} = {node.testValue}\n".fmt
  for element in node.elements:
    result &= print(element, indent+1)
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  print(session.rootNode, -1)
