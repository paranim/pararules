import unittest
import pararules
import tables

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

test "number of conditions != number of facts":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "b"), newStr("color"), newStr("blue"))
  prod.addCondition(Var(name: "y"), newStr("left-of"), Var(name: "z"))
  prod.addCondition(Var(name: "a"), newStr("color"), newStr("maize"))
  prod.addCondition(Var(name: "y"), Var(name: "a"), Var(name: "b"))
  prod.addCondition(Var(name: "x"), newStr("height"), Var(name: "h"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newStr("Bob"), newStr("color"), newStr("blue")))
  session.addFact((newStr("Yair"), newStr("left-of"), newStr("Zach")))
  session.addFact((newStr("Alice"), newStr("color"), newStr("maize")))
  session.addFact((newStr("Yair"), newStr("Alice"), newStr("Bob")))

  session.addFact((newStr("Xavier"), newStr("height"), newInt(72)))
  session.addFact((newStr("Thomas"), newStr("height"), newInt(72)))
  session.addFact((newStr("Gilbert"), newStr("height"), newInt(72)))

  check prodNode.facts.len == 3
  check prodNode.facts[0].len == 5
  check vars["a"] == newStr("Alice")
  check vars["b"] == newStr("Bob")
  check vars["y"] == newStr("Yair")
  check vars["z"] == newStr("Zach")

test "adding facts out of order":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
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
  let prodNode = session.addProduction(prod)
  session.addFact((newStr("Xavier"), newStr("on"), newStr("Yair")))
  session.addFact((newStr("Yair"), newStr("left-of"), newStr("Zach")))
  session.addFact((newStr("Zach"), newStr("color"), newStr("red")))
  session.addFact((newStr("Alex"), newStr("color"), newStr("maize")))
  session.addFact((newStr("Bob"), newStr("color"), newStr("blue")))
  session.addFact((newStr("Charlie"), newStr("color"), newStr("green")))
 
  session.addFact((newStr("Seth"), newStr("on"), newStr("table")))
  session.addFact((newStr("Yair"), newStr("Alex"), newStr("Bob")))
  session.addFact((newStr("Alex"), newStr("left-of"), newStr("Daniel")))

  session.addFact((newStr("Daniel"), newStr("color"), newStr("white")))

  check prodNode.facts.len == 1
  check prodNode.facts[0].len == 10
  check vars["a"] == newStr("Alex")
  check vars["b"] == newStr("Bob")
  check vars["y"] == newStr("Yair")
  check vars["z"] == newStr("Zach")

test "duplicate facts":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "x"), newStr("self"), Var(name: "y"))
  prod.addCondition(Var(name: "x"), newStr("color"), newStr("red"))
  prod.addCondition(Var(name: "y"), newStr("color"), newStr("red"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newStr("b1"), newStr("self"), newStr("b1")))
  session.addFact((newStr("b1"), newStr("color"), newStr("red")))

  check prodNode.facts.len == 1
  check prodNode.facts[0].len == 3

