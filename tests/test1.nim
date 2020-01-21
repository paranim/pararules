import unittest
import pararules
import tables

type
  Attr = enum
    Color, LeftOf, RightOf, Height, On, Self
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
  var ids: Table[string, Data]
  var attrs: Table[string, Attr]
  var values: Table[string, Data]
  var prod = newProduction[Data, Attr, Data](
    proc (i: Table[string, Data], a: Table[string, Attr], v: Table[string, Data]) =
      ids = i
      attrs = a
      values = v
  )
  prod.addCondition(Var(name: "b"), Color, newStr("blue"))
  prod.addCondition(Var(name: "y"), LeftOf, Var(name: "z"))
  prod.addCondition(Var(name: "a"), Color, newStr("maize"))
  prod.addCondition(Var(name: "y"), RightOf, Var(name: "b"))
  prod.addCondition(Var(name: "x"), Height, Var(name: "h"))

  var session = newSession[Data, Attr, Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newStr("Bob"), Color, newStr("blue")))
  session.addFact((newStr("Yair"), LeftOf, newStr("Zach")))
  session.addFact((newStr("Alice"), Color, newStr("maize")))
  session.addFact((newStr("Yair"), RightOf, newStr("Bob")))

  session.addFact((newStr("Xavier"), Height, newInt(72)))
  session.addFact((newStr("Thomas"), Height, newInt(72)))
  session.addFact((newStr("Gilbert"), Height, newInt(72)))

  check prodNode.facts.len == 3
  check prodNode.facts[0].len == 5
  check ids["a"] == newStr("Alice")
  check ids["b"] == newStr("Bob")
  check ids["y"] == newStr("Yair")
  check values["z"] == newStr("Zach")

test "adding facts out of order":
  var ids: Table[string, Data]
  var attrs: Table[string, Attr]
  var values: Table[string, Data]
  var prod = newProduction[Data, Attr, Data](
    proc (i: Table[string, Data], a: Table[string, Attr], v: Table[string, Data]) =
      ids = i
      attrs = a
      values = v
  )
  prod.addCondition(Var(name: "x"), On, Var(name: "y"))
  prod.addCondition(Var(name: "y"), LeftOf, Var(name: "z"))
  prod.addCondition(Var(name: "z"), Color, newStr("red"))
  prod.addCondition(Var(name: "a"), Color, newStr("maize"))
  prod.addCondition(Var(name: "b"), Color, newStr("blue"))
  prod.addCondition(Var(name: "c"), Color, newStr("green"))
  prod.addCondition(Var(name: "d"), Color, newStr("white"))
  prod.addCondition(Var(name: "s"), On, newStr("table"))
  prod.addCondition(Var(name: "y"), RightOf, Var(name: "b"))
  prod.addCondition(Var(name: "a"), LeftOf, Var(name: "d"))

  var session = newSession[Data, Attr, Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newStr("Xavier"), On, newStr("Yair")))
  session.addFact((newStr("Yair"), LeftOf, newStr("Zach")))
  session.addFact((newStr("Zach"), Color, newStr("red")))
  session.addFact((newStr("Alex"), Color, newStr("maize")))
  session.addFact((newStr("Bob"), Color, newStr("blue")))
  session.addFact((newStr("Charlie"), Color, newStr("green")))
 
  session.addFact((newStr("Seth"), On, newStr("table")))
  session.addFact((newStr("Yair"), RightOf, newStr("Bob")))
  session.addFact((newStr("Alex"), LeftOf, newStr("Daniel")))

  session.addFact((newStr("Daniel"), Color, newStr("white")))

  check prodNode.facts.len == 1
  check prodNode.facts[0].len == 10
  check ids["a"] == newStr("Alex")
  check ids["b"] == newStr("Bob")
  check ids["y"] == newStr("Yair")
  check values["z"] == newStr("Zach")

test "duplicate facts":
  var ids: Table[string, Data]
  var attrs: Table[string, Attr]
  var values: Table[string, Data]
  var prod = newProduction[Data, Attr, Data](
    proc (i: Table[string, Data], a: Table[string, Attr], v: Table[string, Data]) =
      ids = i
      attrs = a
      values = v
  )
  prod.addCondition(Var(name: "x"), Self, Var(name: "y"))
  prod.addCondition(Var(name: "x"), Color, newStr("red"))
  prod.addCondition(Var(name: "y"), Color, newStr("red"))

  var session = newSession[Data, Attr, Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newStr("b1"), Self, newStr("b1")))
  session.addFact((newStr("b1"), Color, newStr("red")))

  check prodNode.facts.len == 1
  check prodNode.facts[0].len == 3

