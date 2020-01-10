type
  Field* {.pure.} = enum
    None, Identifier, Attribute, Value
  AlphaNode*[T] = object
    testField*: Field
    testValue*: T
    children*: seq[AlphaNode[T]]
  Session*[T] = object
    rootNode*: AlphaNode[T]

