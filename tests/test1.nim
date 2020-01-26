import unittest
import pararules, pararules/engine
import tables

type
  Person = enum
    Alice, Bob, Charlie, David, George,
    Seth, Thomas, Xavier, Yair, Zach
  Property = enum
    Color, LeftOf, RightOf, Height, On, Self

schema Data:
  id: Person
  attr: Property
  string: string
  int: int

proc Id(x: Person): Data =
  Data(kind: DataKind.Id, id: x)

proc Attr(x: Property): Data =
  Data(kind: DataKind.Attr, attr: x)

proc Str(x: string): Data =
  Data(kind: DataKind.String, string: x)

proc Int(x: int): Data =
  Data(kind: DataKind.Int, int: x)

test "number of conditions != number of facts":
  let prod =
    rule(Data):
      what:
        (b, Color, Str("blue"))
        (y, LeftOf, z)
        (a, Color, Str("maize"))
        (y, RightOf, b)
        (x, Height, h)
      then:
        check a == Id(Alice)
        check b == Id(Bob)
        check y == Id(Yair)
        check z == Id(Zach)

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Color), Str("blue")))
  session.addFact((Id(Yair), Attr(LeftOf), Id(Zach)))
  session.addFact((Id(Alice), Attr(Color), Str("maize")))
  session.addFact((Id(Yair), Attr(RightOf), Id(Bob)))

  session.addFact((Id(Xavier), Attr(Height), Int(72)))
  session.addFact((Id(Thomas), Attr(Height), Int(72)))
  session.addFact((Id(George), Attr(Height), Int(72)))

  check prodNode.debugFacts.len == 3
  check prodNode.debugFacts[0].len == 5

test "adding facts out of order":
  let prod =
    rule(Data):
      what:
        (x, On, y)
        (y, LeftOf, z)
        (z, Color, Str("red"))
        (a, Color, Str("maize"))
        (b, Color, Str("blue"))
        (c, Color, Str("green"))
        (d, Color, Str("white"))
        (s, On, Str("table"))
        (y, RightOf, b)
        (a, LeftOf, d)
      then:
        check a == Id(Alice)
        check b == Id(Bob)
        check y == Id(Yair)
        check z == Id(Zach)

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

  check prodNode.debugFacts.len == 1
  check prodNode.debugFacts[0].len == 10

test "duplicate facts":
  let prod =
    rule(Data):
      what:
        (x, Self, y)
        (x, Color, Str("red"))
        (y, Color, Str("red"))

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Self), Id(Bob)))
  session.addFact((Id(Bob), Attr(Color), Str("red")))

  check prodNode.debugFacts.len == 1
  check prodNode.debugFacts[0].len == 3

test "removing facts":
  let prod =
    rule(Data):
      what:
        (b, Color, Str("blue"))
        (y, LeftOf, z)
        (a, Color, Str("maize"))
        (y, RightOf, b)

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Color), Str("blue")))
  session.addFact((Id(Yair), Attr(LeftOf), Id(Zach)))
  session.addFact((Id(Alice), Attr(Color), Str("maize")))
  session.addFact((Id(Yair), Attr(RightOf), Id(Bob)))
  check prodNode.debugFacts.len == 1

  session.removeFact((Id(Yair), Attr(RightOf), Id(Bob)))
  check prodNode.debugFacts.len == 0
  check prodNode.getParent.debugFacts.len == 1
  check prodNode.getParent.debugFacts[0].len == 3

  session.removeFact((Id(Bob), Attr(Color), Str("blue")))
  check prodNode.debugFacts.len == 0
  check prodNode.getParent.debugFacts.len == 0

test "updating facts":
  var zVal: Data

  let prod =
    rule(Data):
      what:
        (b, Color, Str("blue"))
        (y, LeftOf, z)
        (a, Color, Str("maize"))
        (y, RightOf, b)
      then:
        zVal = z

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Color), Str("blue")))
  session.addFact((Id(Yair), Attr(LeftOf), Id(Zach)))
  session.addFact((Id(Alice), Attr(Color), Str("maize")))
  session.addFact((Id(Yair), Attr(RightOf), Id(Bob)))
  check prodNode.debugFacts.len == 1
  check zVal == Id(Zach)

  session.addFact((Id(Yair), Attr(LeftOf), Id(Xavier)))
  check prodNode.debugFacts.len == 1
  check zVal == Id(Xavier)

test "updating facts in different alpha nodes":
  let prod =
    rule(Data):
      what:
        (b, Color, Str("blue"))
        (y, LeftOf, Id(Zach))
        (a, Color, Str("maize"))
        (y, RightOf, b)

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Color), Str("blue")))
  session.addFact((Id(Yair), Attr(LeftOf), Id(Zach)))
  session.addFact((Id(Alice), Attr(Color), Str("maize")))
  session.addFact((Id(Yair), Attr(RightOf), Id(Bob)))
  check prodNode.debugFacts.len == 1

  session.addFact((Id(Yair), Attr(LeftOf), Id(Xavier)))
  check prodNode.debugFacts.len == 0

test "complex conditions":
  let prod =
    rule(Data):
      what:
        (b, Color, Str("blue"))
        (y, LeftOf, z)
        (a, Color, Str("maize"))
        (y, RightOf, b)
      cond:
        z != Id(Zach)

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((Id(Bob), Attr(Color), Str("blue")))
  session.addFact((Id(Yair), Attr(LeftOf), Id(Zach)))
  session.addFact((Id(Alice), Attr(Color), Str("maize")))
  session.addFact((Id(Yair), Attr(RightOf), Id(Bob)))
  check prodNode.debugFacts.len == 0

  session.addFact((Id(Yair), Attr(LeftOf), Id(Charlie)))
  check prodNode.debugFacts.len == 1

