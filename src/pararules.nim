import strformat, sequtils

type
  Field* {.pure.} = enum
    None, Identifier, Attribute, Value
  Fact*[T] = tuple[id: T, attr: T, value: T]
  AlphaNode*[T] = object
    testField*: Field
    testValue*: T
    outputMemory*: seq[Fact[T]]
    children*: seq[AlphaNode[T]]
  Session*[T] = object
    rootNode: AlphaNode[T]

proc addNode(node: var AlphaNode, newNode: AlphaNode) =
  for child in node.children.mitems():
    if child.testField == newNode.testField and child.testValue == newNode.testValue:
      for newChild in newNode.children:
        child.addNode(newChild)
      return
  node.children.add(newNode)

proc addNode*(session: var Session, newNode: AlphaNode) =
  session.rootNode.addNode(newNode)

proc activateMemory(node: var AlphaNode, element: Fact) =
  node.outputMemory.add(element)

proc addFact(node: var AlphaNode, element: Fact) =
  let val = case node.testField:
            of Field.None: node.testValue
            of Field.Identifier: element[0]
            of Field.Attribute: element[1]
            of Field.Value: element[2]
  if val != node.testValue:
    return
  elif node.testField != Field.None:
    node.activateMemory(element)
  for child in node.children.mitems():
    child.addFact(element)

proc addFact*(session: var Session, element: Fact) =
  session.rootNode.addFact(element)

proc print(element: Fact, indent: int): string =
  if indent >= 0:
    for i in 0..indent-1:
      result &= "  "
  result &= "Fact = {element} \n".fmt

proc print(node: AlphaNode, indent: int): string =
  if indent >= 0:
    for i in 0..indent-1:
      result &= "  "
    result &= "{node.testField} = {node.testValue}\n".fmt
  for element in node.outputMemory:
    result &= print(element, indent+1)
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  print(session.rootNode, -1)
