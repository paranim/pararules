import unittest
import pararules

type
  DataType = enum
    Var, Str, Int
  Data = object
    case kind: DataType
    of Var: varVal: string
    of Str: strVal: string
    of Int: intVal: int

proc newVar(val: string): Data =
  Data(kind: Var, varval: val)

proc newStr(val: string): Data =
  Data(kind: Str, strVal: val)

proc newInt(val: int): Data =
  Data(kind: Int, intVal: val)

test "can create session":
  var session = Session[Data]()
  var on = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("on"))
  var table = AlphaNode[Data](testField: Field.Value, testValue: newStr("table"))
  var wme = (id: newInt(1), attr: newStr("on"), value: newStr("table"))
  table.outputMemory.add(wme)
  on.children.add(table)
  session.rootNode.children.add(on)
  echo session
