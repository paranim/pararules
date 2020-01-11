type
  Field* {.pure.} = enum
    None, Identifier, Attribute, Value
  WME*[T] = tuple[id: T, attr: T, value: T]
  AlphaNode*[T] = object
    testField*: Field
    testValue*: T
    outputMemory*: seq[WME[T]]
    children*: seq[AlphaNode[T]]
  Session*[T] = object
    rootNode*: AlphaNode[T]

