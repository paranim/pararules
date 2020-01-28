import unittest
import pararules
from pararules/engine import getParent
import tables

type
  Id = enum
    Alice, Bob, Charlie, David, George,
    Seth, Thomas, Xavier, Yair, Zach
  Attr = enum
    Color, LeftOf, RightOf, Height, On, Self

schema Data(Id, Attr):
  Color: string
  LeftOf: Id
  RightOf: Id
  Height: int
  On: string
  Self: Id

test "number of conditions != number of facts":
  var session = newSession(Data)
  session.add:
    rule numCondsAndFacts(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
        (x, Height, h)
      then:
        check a == Alice
        check b == Bob
        check y == Yair
        check z == Zach

  let prodNode = session.prodNodes["numCondsAndFacts"]

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)

  session.insert(Xavier, Height, 72)
  session.insert(Thomas, Height, 72)
  session.insert(George, Height, 72)

  check prodNode.debugFacts.len == 3
  check prodNode.debugFacts[0].len == 5

test "adding facts out of order":
  var session = newSession(Data)
  session.add:
    rule outOfOrder(Data):
      what:
        (x, RightOf, y)
        (y, LeftOf, z)
        (z, Color, "red")
        (a, Color, "maize")
        (b, Color, "blue")
        (c, Color, "green")
        (d, Color, "white")
        (s, On, "table")
        (y, RightOf, b)
        (a, LeftOf, d)
      then:
        check a == Alice
        check b == Bob
        check y == Yair
        check z == Zach

  let prodNode = session.prodNodes["outOfOrder"]

  session.insert(Xavier, RightOf, Yair)
  session.insert(Yair, LeftOf, Zach)
  session.insert(Zach, Color, "red")
  session.insert(Alice, Color, "maize")
  session.insert(Bob, Color, "blue")
  session.insert(Charlie, Color, "green")
 
  session.insert(Seth, On, "table")
  session.insert(Yair, RightOf, Bob)
  session.insert(Alice, LeftOf, David)

  session.insert(David, Color, "white")

  check prodNode.debugFacts.len == 1
  check prodNode.debugFacts[0].len == 10

test "duplicate facts":
  var session = newSession(Data)
  session.add:
    rule duplicateFacts(Data):
      what:
        (x, Self, y)
        (x, Color, "red")
        (y, Color, "red")

  let prodNode = session.prodNodes["duplicateFacts"]

  session.insert(Bob, Self, Bob)
  session.insert(Bob, Color, "red")

  check prodNode.debugFacts.len == 1
  check prodNode.debugFacts[0].len == 3

test "removing facts":
  var session = newSession(Data)
  session.add:
    rule removingFacts(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)

  let prodNode = session.prodNodes["removingFacts"]

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)
  check prodNode.debugFacts.len == 1

  session.remove(Yair, RightOf, Bob)
  check prodNode.debugFacts.len == 0
  check prodNode.getParent.debugFacts.len == 1
  check prodNode.getParent.debugFacts[0].len == 3

  session.remove(Bob, Color, "blue")
  check prodNode.debugFacts.len == 0
  check prodNode.getParent.debugFacts.len == 0

test "updating facts":
  var session = newSession(Data)
  var zVal: Id
  session.add:
    rule updatingFacts(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
      then:
        zVal = z

  let prodNode = session.prodNodes["updatingFacts"]

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)
  check prodNode.debugFacts.len == 1
  check zVal == Zach

  session.insert(Yair, LeftOf, Xavier)
  check prodNode.debugFacts.len == 1
  check zVal == Xavier

test "updating facts in different alpha nodes":
  var session = newSession(Data)
  session.add:
    rule updatingFactsDiffNodes(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, Zach)
        (a, Color, "maize")
        (y, RightOf, b)

  let prodNode = session.prodNodes["updatingFactsDiffNodes"]

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)
  check prodNode.debugFacts.len == 1

  session.insert(Yair, LeftOf, Xavier)
  check prodNode.debugFacts.len == 0

test "complex conditions":
  var session = newSession(Data)
  session.add:
    rule complexCond(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
      cond:
        z != Zach

  let prodNode = session.prodNodes["complexCond"]

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)
  check prodNode.debugFacts.len == 0

  session.insert(Yair, LeftOf, Charlie)
  check prodNode.debugFacts.len == 1

test "queries":
  let getPerson =
    rule getPerson(Data):
      what:
        (id, Color, color)
        (id, LeftOf, leftOf)
        (id, Height, height)

  var session = newSession(Data)
  session.add(getPerson)

  session.insert(Bob, Color, "blue")
  session.insert(Bob, LeftOf, Zach)
  session.insert(Bob, Height, 72)

  session.insert(Alice, Color, "green")
  session.insert(Alice, LeftOf, Bob)
  session.insert(Alice, Height, 64)

  let loc = session.find(getPerson, id: Bob)
  check loc >= 0
  let res = session.get(getPerson, loc)
  check res.id == Bob
  check res.color == "blue"
  check res.leftOf == Zach
  check res.height == 72

# this one is not used...
# it's just here to make sure we can define
# multiple schemas in one module
schema Stuff(Id, Attr):
  Color: int
  LeftOf: Id
  RightOf: Id
  Height: float
  On: string
  Self: Id
