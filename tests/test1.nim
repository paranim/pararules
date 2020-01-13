import unittest
import pararules

type
  DataType = enum
    Str, Int
  Data = object
    case kind: DataType
    of Str: strVal: string
    of Int: intVal: int

proc `==`(x, y: Data): bool =
  x.kind == y.kind and
    (case x.kind:
     of Str: x.strVal == y.strVal
     of Int: x.intVal == y.intVal)

proc newStr(val: string): Data =
  Data(kind: Str, strVal: val)

proc newInt(val: int): Data =
  Data(kind: Int, intVal: val)

test "can create session":
  var session = newSession[Data]()
  session.addCondition(Var(name: "x"), newStr("on"), Var(name: "y"))
  session.addCondition(Var(name: "y"), newStr("left-of"), Var(name: "z"))
  session.addCondition(Var(name: "z"), newStr("color"), newStr("red"))
  session.addCondition(Var(name: "a"), newStr("color"), newStr("maize"))
  session.addCondition(Var(name: "b"), newStr("color"), newStr("blue"))
  session.addCondition(Var(name: "c"), newStr("color"), newStr("green"))
  session.addCondition(Var(name: "d"), newStr("color"), newStr("white"))
  session.addCondition(Var(name: "s"), newStr("on"), newStr("table"))
  session.addCondition(Var(name: "y"), Var(name: "a"), Var(name: "b"))
  session.addCondition(Var(name: "a"), newStr("left-of"), Var(name: "d"))
  session.addFact((newInt(1), newStr("on"), newInt(2)))
  session.addFact((newInt(1), newStr("color"), newStr("red")))
  echo session

