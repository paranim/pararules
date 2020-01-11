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

proc `==`(x, y: Data): bool =
  x.kind == y.kind and
    (case x.kind:
     of Var: x.varVal == y.varVal
     of Str: x.strVal == y.strVal
     of Int: x.intVal == y.intVal)

proc newVar(val: string): Data =
  Data(kind: Var, varval: val)

proc newStr(val: string): Data =
  Data(kind: Str, strVal: val)

proc newInt(val: int): Data =
  Data(kind: Int, intVal: val)

test "can create session":
  var session = Session[Data]()
  let c1 = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("on"))
  let c2 = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("left-of"))
  let c3 = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("color"),
             children: @[AlphaNode[Data](testField: Field.Value, testValue: newStr("red"))])
  let c4 = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("color"),
             children: @[AlphaNode[Data](testField: Field.Value, testValue: newStr("maize"))])
  let c5 = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("color"),
             children: @[AlphaNode[Data](testField: Field.Value, testValue: newStr("blue"))])
  let c6 = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("color"),
             children: @[AlphaNode[Data](testField: Field.Value, testValue: newStr("green"))])
  let c7 = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("color"),
             children: @[AlphaNode[Data](testField: Field.Value, testValue: newStr("white"))])
  let c8 = AlphaNode[Data](testField: Field.Attribute, testValue: newStr("on"),
             children: @[AlphaNode[Data](testField: Field.Value, testValue: newStr("table"))])
  session.addNode(c1)
  session.addNode(c2)
  session.addNode(c3)
  session.addNode(c4)
  session.addNode(c5)
  session.addNode(c6)
  session.addNode(c7)
  session.addNode(c8)
  echo session

