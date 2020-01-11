import strformat

type
  Field* {.pure.} = enum
    None, Identifier, Attribute, Value
  Entry*[T] = object
    id*: T
    attr*: T
    value*: T
  AlphaNode*[T] = object
    testField*: Field
    testValue*: T
    outputMemory*: seq[Entry[T]]
    children*: seq[AlphaNode[T]]
  Session*[T] = object
    rootNode*: AlphaNode[T]

proc addNode*(node: var AlphaNode, newNode: AlphaNode) =
  for child in node.children.mitems():
    if child.testField == newNode.testField and child.testValue == newNode.testValue:
      for newChild in newNode.children:
        child.addNode(newChild)
      return
  node.children.add(newNode)

proc addNode*(session: var Session, newNode: AlphaNode) =
  session.rootNode.addNode(newNode)

proc print(node: AlphaNode, indent: int): string =
  if indent >= 0:
    for i in 0..indent-1:
      result &= "  "
    result &= "{node.testField} = {node.testValue}\n".fmt
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  print(session.rootNode, -1)
