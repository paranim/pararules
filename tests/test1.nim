import unittest
import pararules
import tables
import patty

type
  Person = enum
    Alice, Bob, Charlie, David, George,
    Seth, Thomas, Xavier, Yair, Zach
  Property = enum
    Color, LeftOf, RightOf, Height, On, Self

variant Data:
  Id(idVal: Person)
  Attr(attrVal: Property)
  Str(strVal: string)
  Int(intVal: int)

test "number of conditions != number of facts":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "b"), Attr(Color), Str("blue"))
  prod.addCondition(Var(name: "y"), Attr(LeftOf), Var(name: "z"))
  prod.addCondition(Var(name: "a"), Attr(Color), Str("maize"))
  prod.addCondition(Var(name: "y"), Attr(RightOf), Var(name: "b"))
  prod.addCondition(Var(name: "x"), Attr(Height), Var(name: "h"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Color), Str("blue")))
  session.addFact((Id(Yair), Attr(LeftOf), Id(Zach)))
  session.addFact((Id(Alice), Attr(Color), Str("maize")))
  session.addFact((Id(Yair), Attr(RightOf), Id(Bob)))

  session.addFact((Id(Xavier), Attr(Height), Int(72)))
  session.addFact((Id(Thomas), Attr(Height), Int(72)))
  session.addFact((Id(George), Attr(Height), Int(72)))

  check prodNode.facts.len == 3
  check prodNode.facts[0].len == 5
  check vars["a"] == Id(Alice)
  check vars["b"] == Id(Bob)
  check vars["y"] == Id(Yair)
  check vars["z"] == Id(Zach)

test "adding facts out of order":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "x"), Attr(On), Var(name: "y"))
  prod.addCondition(Var(name: "y"), Attr(LeftOf), Var(name: "z"))
  prod.addCondition(Var(name: "z"), Attr(Color), Str("red"))
  prod.addCondition(Var(name: "a"), Attr(Color), Str("maize"))
  prod.addCondition(Var(name: "b"), Attr(Color), Str("blue"))
  prod.addCondition(Var(name: "c"), Attr(Color), Str("green"))
  prod.addCondition(Var(name: "d"), Attr(Color), Str("white"))
  prod.addCondition(Var(name: "s"), Attr(On), Str("table"))
  prod.addCondition(Var(name: "y"), Attr(RightOf), Var(name: "b"))
  prod.addCondition(Var(name: "a"), Attr(LeftOf), Var(name: "d"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Xavier), Attr(On), Id(Yair)))
  session.addFact((Id(Yair), Attr(LeftOf), Id(Zach)))
  session.addFact((Id(Zach), Attr(Color), Str("red")))
  session.addFact((Id(Alice), Attr(Color), Str("maize")))
  session.addFact((Id(Bob), Attr(Color), Str("blue")))
  session.addFact((Id(Charlie), Attr(Color), Str("green")))
 
  session.addFact((Id(Seth), Attr(On), Str("table")))
  session.addFact((Id(Yair), Attr(RightOf), Id(Bob)))
  session.addFact((Id(Alice), Attr(LeftOf), Id(David)))

  session.addFact((Id(David), Attr(Color), Str("white")))

  check prodNode.facts.len == 1
  check prodNode.facts[0].len == 10
  check vars["a"] == Id(Alice)
  check vars["b"] == Id(Bob)
  check vars["y"] == Id(Yair)
  check vars["z"] == Id(Zach)

test "duplicate facts":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "x"), Attr(Self), Var(name: "y"))
  prod.addCondition(Var(name: "x"), Attr(Color), Str("red"))
  prod.addCondition(Var(name: "y"), Attr(Color), Str("red"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Self), Id(Bob)))
  session.addFact((Id(Bob), Attr(Color), Str("red")))

  check prodNode.facts.len == 1
  check prodNode.facts[0].len == 3

test "removing facts":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "b"), Attr(Color), Str("blue"))
  prod.addCondition(Var(name: "y"), Attr(LeftOf), Var(name: "z"))
  prod.addCondition(Var(name: "a"), Attr(Color), Str("maize"))
  prod.addCondition(Var(name: "y"), Attr(RightOf), Var(name: "b"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Color), Str("blue")))
  session.addFact((Id(Yair), Attr(LeftOf), Id(Zach)))
  session.addFact((Id(Alice), Attr(Color), Str("maize")))
  session.addFact((Id(Yair), Attr(RightOf), Id(Bob)))
  check prodNode.facts.len == 1

  session.removeFact((Id(Yair), Attr(RightOf), Id(Bob)))
  check prodNode.facts.len == 0
  check prodNode.getParent.facts.len == 1
  check prodNode.getParent.facts[0].len == 3

  session.removeFact((Id(Bob), Attr(Color), Str("blue")))
  check prodNode.facts.len == 0
  check prodNode.getParent.facts.len == 0

test "updating facts":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "b"), Attr(Color), Str("blue"))
  prod.addCondition(Var(name: "y"), Attr(LeftOf), Var(name: "z"))
  prod.addCondition(Var(name: "a"), Attr(Color), Str("maize"))
  prod.addCondition(Var(name: "y"), Attr(RightOf), Var(name: "b"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Color), Str("blue")))
  session.addFact((Id(Yair), Attr(LeftOf), Id(Zach)))
  session.addFact((Id(Alice), Attr(Color), Str("maize")))
  session.addFact((Id(Yair), Attr(RightOf), Id(Bob)))
  check prodNode.facts.len == 1
  check vars["z"] == Id(Zach)

  session.addFact((Id(Yair), Attr(LeftOf), Id(Xavier)))
  check vars["z"] == Id(Xavier)

