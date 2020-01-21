import unittest
import pararules
import tables
import patty

variant Data:
  Str(strVal: string)
  Int(intVal: int)

test "number of conditions != number of facts":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "b"), Str("color"), Str("blue"))
  prod.addCondition(Var(name: "y"), Str("left-of"), Var(name: "z"))
  prod.addCondition(Var(name: "a"), Str("color"), Str("maize"))
  prod.addCondition(Var(name: "y"), Var(name: "a"), Var(name: "b"))
  prod.addCondition(Var(name: "x"), Str("height"), Var(name: "h"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Str("Bob"), Str("color"), Str("blue")))
  session.addFact((Str("Yair"), Str("left-of"), Str("Zach")))
  session.addFact((Str("Alice"), Str("color"), Str("maize")))
  session.addFact((Str("Yair"), Str("Alice"), Str("Bob")))

  session.addFact((Str("Xavier"), Str("height"), Int(72)))
  session.addFact((Str("Thomas"), Str("height"), Int(72)))
  session.addFact((Str("Gilbert"), Str("height"), Int(72)))

  check prodNode.facts.len == 3
  check prodNode.facts[0].len == 5
  check vars["a"] == Str("Alice")
  check vars["b"] == Str("Bob")
  check vars["y"] == Str("Yair")
  check vars["z"] == Str("Zach")

test "adding facts out of order":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "x"), Str("on"), Var(name: "y"))
  prod.addCondition(Var(name: "y"), Str("left-of"), Var(name: "z"))
  prod.addCondition(Var(name: "z"), Str("color"), Str("red"))
  prod.addCondition(Var(name: "a"), Str("color"), Str("maize"))
  prod.addCondition(Var(name: "b"), Str("color"), Str("blue"))
  prod.addCondition(Var(name: "c"), Str("color"), Str("green"))
  prod.addCondition(Var(name: "d"), Str("color"), Str("white"))
  prod.addCondition(Var(name: "s"), Str("on"), Str("table"))
  prod.addCondition(Var(name: "y"), Var(name: "a"), Var(name: "b"))
  prod.addCondition(Var(name: "a"), Str("left-of"), Var(name: "d"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Str("Xavier"), Str("on"), Str("Yair")))
  session.addFact((Str("Yair"), Str("left-of"), Str("Zach")))
  session.addFact((Str("Zach"), Str("color"), Str("red")))
  session.addFact((Str("Alex"), Str("color"), Str("maize")))
  session.addFact((Str("Bob"), Str("color"), Str("blue")))
  session.addFact((Str("Charlie"), Str("color"), Str("green")))
 
  session.addFact((Str("Seth"), Str("on"), Str("table")))
  session.addFact((Str("Yair"), Str("Alex"), Str("Bob")))
  session.addFact((Str("Alex"), Str("left-of"), Str("Daniel")))

  session.addFact((Str("Daniel"), Str("color"), Str("white")))

  check prodNode.facts.len == 1
  check prodNode.facts[0].len == 10
  check vars["a"] == Str("Alex")
  check vars["b"] == Str("Bob")
  check vars["y"] == Str("Yair")
  check vars["z"] == Str("Zach")

test "duplicate facts":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "x"), Str("self"), Var(name: "y"))
  prod.addCondition(Var(name: "x"), Str("color"), Str("red"))
  prod.addCondition(Var(name: "y"), Str("color"), Str("red"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Str("b1"), Str("self"), Str("b1")))
  session.addFact((Str("b1"), Str("color"), Str("red")))

  check prodNode.facts.len == 1
  check prodNode.facts[0].len == 3

test "removing facts":
  var vars: Table[string, Data]
  var prod = newProduction[Data](proc (v: Table[string, Data]) = vars = v)
  prod.addCondition(Var(name: "b"), Str("color"), Str("blue"))
  prod.addCondition(Var(name: "y"), Str("left-of"), Var(name: "z"))
  prod.addCondition(Var(name: "a"), Str("color"), Str("maize"))
  prod.addCondition(Var(name: "y"), Var(name: "a"), Var(name: "b"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Str("Bob"), Str("color"), Str("blue")))
  session.addFact((Str("Yair"), Str("left-of"), Str("Zach")))
  session.addFact((Str("Alice"), Str("color"), Str("maize")))
  session.addFact((Str("Yair"), Str("Alice"), Str("Bob")))
  check prodNode.facts.len == 1

  session.removeFact((Str("Bob"), Str("color"), Str("blue")))
  check prodNode.facts.len == 0

