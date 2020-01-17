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

test "figure 2.2":
  var prod = newProduction[Data]()
  prod.addCondition(Var(name: "b"), newStr("color"), newStr("blue"))
  prod.addCondition(Var(name: "y"), newStr("left-of"), Var(name: "z"))
  prod.addCondition(Var(name: "a"), newStr("color"), newStr("maize"))
  prod.addCondition(Var(name: "y"), Var(name: "a"), Var(name: "b"))
  var session = newSession[Data]()
  session.addProduction(prod)
  session.addFact((newStr("Bob"), newStr("color"), newStr("blue")))
  session.addFact((newStr("Yair"), newStr("left-of"), newStr("Zach")))
  session.addFact((newStr("Alice"), newStr("color"), newStr("maize")))
  session.addFact((newStr("Yair"), newStr("Alice"), newStr("Bob")))
  echo session

#[
test "figure 2.4":
  var prod = newProduction[Data]()
  prod.addCondition(Var(name: "x"), newStr("on"), Var(name: "y"))
  prod.addCondition(Var(name: "y"), newStr("left-of"), Var(name: "z"))
  prod.addCondition(Var(name: "z"), newStr("color"), newStr("red"))
  prod.addCondition(Var(name: "a"), newStr("color"), newStr("maize"))
  prod.addCondition(Var(name: "b"), newStr("color"), newStr("blue"))
  prod.addCondition(Var(name: "c"), newStr("color"), newStr("green"))
  prod.addCondition(Var(name: "d"), newStr("color"), newStr("white"))
  prod.addCondition(Var(name: "s"), newStr("on"), newStr("table"))
  prod.addCondition(Var(name: "y"), Var(name: "a"), Var(name: "b"))
  prod.addCondition(Var(name: "a"), newStr("left-of"), Var(name: "d"))
  var session = newSession[Data]()
  session.addProduction(prod)
  session.addFact((newInt(1), newStr("on"), newInt(2)))
  session.addFact((newInt(1), newStr("color"), newStr("red")))
  ]#

