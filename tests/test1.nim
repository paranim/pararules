import unittest
import pararules

type
  DataType = enum
    String, Int
  Data = object
    case kind: DataType
    of String: strVal: string
    of Int: intVal: int

proc newStr(val: string): Data =
  Data(kind: String, strVal: val)

proc newInt(val: int): Data =
  Data(kind: Int, intVal: val)

test "can create session":
  var session = Session[Data]()
  var node = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("color"))
  session.rootNode.children.add(node)
  var wme = (id: 1, attr: newStr("size"), value: newInt(100))
  session.rootNode.outputMemory.add(wme)
  echo session
