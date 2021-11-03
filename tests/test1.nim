import unittest
import pararules
import tables, sets

type
  People = seq[tuple[id: int, color: string, leftOf: int, height: int]]
  Id* = enum
    Alice, Bob, Charlie, David, George,
    Seth, Thomas, Xavier, Yair, Zach,
    Derived,
  Attr* = enum
    Color, LeftOf, RightOf, Height, On, Self,
    AllPeople,

schema Fact(Id, Attr):
  Color: string
  LeftOf: Id
  RightOf: Id
  Height: int
  On: string
  Self: Id
  AllPeople: People

proc `==`(a: int, b: Id): bool =
  a == b.ord

test "number of conditions != number of facts":
  var session = initSession(Fact)
  let rule1 =
    rule numCondsAndFacts(Fact):
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
  session.add(rule1)

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)

  session.insert(Xavier, Height, 72)
  session.insert(Thomas, Height, 72)
  session.insert(George, Height, 72)

  check session.queryAll(rule1).len == 3

test "adding facts out of order":
  var session = initSession(Fact)
  let rule1 =
    rule outOfOrder(Fact):
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
  session.add(rule1)

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

  check session.queryAll(rule1).len == 1

test "duplicate facts":
  var session = initSession(Fact)
  let rule1 =
    rule duplicateFacts(Fact):
      what:
        (x, Self, y)
        (x, Color, c)
        (y, Color, c)
  session.add(rule1)

  session.insert(Bob, Self, Bob)
  session.insert(Bob, Color, "red")

  check session.queryAll(rule1).len == 1
  check session.query(rule1).c == "red"

  # update *both* duplicate facts from red to green
  session.insert(Bob, Color, "green")

  check session.queryAll(rule1).len == 1
  check session.query(rule1).c == "green"

test "removing facts":
  var session = initSession(Fact)
  let rule1 =
    rule removingFacts(Fact):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
  session.add(rule1)

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)
  check session.queryAll(rule1).len == 1

  session.retract(Yair, RightOf, Bob)
  check session.queryAll(rule1).len == 0

  session.retract(Bob, Color) # value parameter is not required
  check session.queryAll(rule1).len == 0

  # re-insert to make sure idAttrNodes was cleared correctly
  session.insert(Bob, Color, "blue")
  session.insert(Yair, RightOf, Bob)
  check session.queryAll(rule1).len == 1

test "updating facts":
  var session = initSession(Fact, autoFire = false)
  var zVal: int
  let rule1 =
    rule updatingFacts(Fact):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
      then:
        zVal = z
  session.add(rule1)

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)
  session.fireRules()
  check session.queryAll(rule1).len == 1
  check zVal == Zach

  session.insert(Yair, LeftOf, Xavier)
  session.fireRules()
  check session.queryAll(rule1).len == 1
  check zVal == Xavier

test "updating facts in different alpha nodes":
  var session = initSession(Fact)
  let rule1 =
    rule updatingFactsDiffNodes(Fact):
      what:
        (b, Color, "blue")
        (y, LeftOf, Zach)
        (a, Color, "maize")
        (y, RightOf, b)
  session.add(rule1)

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)
  check session.queryAll(rule1).len == 1

  session.insert(Yair, LeftOf, Xavier)
  check session.queryAll(rule1).len == 0

test "facts can be stored in multiple alpha nodes":
  var session = initSession(Fact)
  var alice, zach: int
  session.add:
    rule rule1(Fact):
      what:
        (a, LeftOf, Zach)
      then:
        alice = a
  session.add:
    rule rule2(Fact):
      what:
        (a, LeftOf, z)
      then:
        zach = z
  session.insert(Alice, LeftOf, Zach)
  check alice == Alice
  check zach == Zach

test "complex conditions":
  var session = initSession(Fact)
  let rule1 =
    rule complexCond(Fact):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
      cond:
        z != Zach
  session.add(rule1)

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, Zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)
  check session.queryAll(rule1).len == 0

  session.insert(Yair, LeftOf, Charlie)
  check session.queryAll(rule1).len == 1

test "out-of-order joins between id and value":
  var session = initSession(Fact)
  let rule1 =
    rule rule1(Fact):
      what:
        (b, RightOf, Alice)
        (y, RightOf, b)
        (b, Color, "blue")
  session.add(rule1)

  session.insert(Bob, RightOf, Alice)
  session.insert(Bob, Color, "blue")
  session.insert(Yair, RightOf, Bob)
  check session.queryAll(rule1).len == 1

# this was failing because we weren't testing conditions
# in join nodes who are children of the root memory node
test "simple conditions":
  var count = 0

  var session = initSession(Fact)
  session.add:
    rule simpleCond(Fact):
      what:
        (b, Color, "blue")
      cond:
        false
      then:
        count += 1

  session.insert(Bob, Color, "blue")

  check count == 0

test "queries":
  let getPerson =
    rule getPerson(Fact):
      what:
        (id, Color, color)
        (id, LeftOf, leftOf)
        (id, Height, height)

  var session = initSession(Fact)
  session.add(getPerson)

  session.insert(Bob, Color, "blue")
  session.insert(Bob, LeftOf, Zach)
  session.insert(Bob, Height, 72)

  session.insert(Alice, Color, "green")
  session.insert(Alice, LeftOf, Bob)
  session.insert(Alice, Height, 64)

  session.insert(Charlie, Color, "red")
  session.insert(Charlie, LeftOf, Alice)
  session.insert(Charlie, Height, 72)

  let loc = session.find(getPerson, id = Bob)
  check loc >= 0
  let res = session.get(getPerson, loc)
  check res.id == Bob
  check res.color == "blue"
  check res.leftOf == Zach
  check res.height == 72

  let resQuery = session.query(getPerson, id = Bob)
  check resQuery == res

  let locs = session.findAll(getPerson, height = 72)
  check locs.len == 2

test "query all facts":
  let getPerson =
    rule getPerson(Fact):
      what:
        (id, Color, color)
        (id, LeftOf, leftOf)
        (id, Height, height)

  var session = initSession(Fact)
  session.add(getPerson)

  session.insert(Bob, Color, "blue")
  session.insert(Bob, LeftOf, Zach)
  session.insert(Bob, Height, 72)

  session.insert(Alice, Color, "green")
  session.insert(Alice, LeftOf, Bob)
  session.insert(Alice, Height, 64)

  session.insert(Charlie, Color, "red")
  session.insert(Charlie, LeftOf, Alice)
  session.insert(Charlie, Height, 72)

  # insert and retract a fact to make sure
  # it isn't returned by queryAll
  session.insert(Zach, Color, "blue")
  session.retract(Zach, Color)

  let facts = session.queryAll()
  check facts.len == 9

  # make a new session and insert the facts we retrieved

  var session2 = initSession(Fact)
  session2.add(getPerson)

  for fact in facts:
    session2.insert(Id(fact.id), Attr(fact.attr), fact.value)

  # check that the queries work

  let loc = session2.find(getPerson, id = Bob)
  check loc >= 0
  let res = session2.get(getPerson, loc)
  check res.id == Bob
  check res.color == "blue"
  check res.leftOf == Zach
  check res.height == 72

  let resQuery = session2.query(getPerson, id = Bob)
  check resQuery == res

  let locs = session2.findAll(getPerson, height = 72)
  check locs.len == 2

  # try unwrapping the values

  for fact in facts:
    case Attr(fact.attr):
      of Color:
        discard unwrap(fact.value, string)
      of LeftOf, Height:
        discard unwrap(fact.value, int)
      else:
        discard

test "creating a ruleset":
  let rules =
    ruleset:
      rule bob(Fact):
        what:
          (b, Color, "blue")
          (b, RightOf, a)
        then:
          check a == Alice
          check b == Bob
      rule alice(Fact):
        what:
          (a, Color, "red")
          (a, LeftOf, b)
        then:
          check a == Alice
          check b == Bob

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Bob, Color, "blue")
  session.insert(Bob, RightOf, Alice)
  session.insert(Alice, Color, "red")
  session.insert(Alice, LeftOf, Bob)

  check session.queryAll(rules.bob).len == 1
  check session.queryAll(rules.alice).len == 1

test "don't trigger rule when updating certain facts":
  var count = 0

  var session = initSession(Fact)
  session.add:
    rule dontTrigger(Fact):
      what:
        (b, Color, "blue")
        (a, Color, c, then = false)
      then:
        count += 1

  session.insert(Bob, Color, "blue")
  session.insert(Alice, Color, "red")
  session.insert(Alice, Color, "maize")

  check count == 1

test "inserting inside a rule is delayed":
  let rules =
    ruleset:
      rule firstRule(Fact):
        what:
          (b, Color, "blue")
          (a, Color, c, then = false)
        then:
          # if this insertion is not delayed, it will throw an error
          session.insert(Alice, Color, "maize")
      rule secondRule(Fact):
        what:
          (b, Color, "blue")
          (a, Color, c, then = false)

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Bob, Color, "blue")
  session.insert(Alice, Color, "red")

test "inserting inside a rule can trigger rule more than once":
  var count = 0
  let rules =
    ruleset:
      rule firstRule(Fact):
        what:
          (b, Color, "blue")
        then:
          session.insert(Alice, Color, "maize")
          session.insert(Charlie, Color, "gold")
      rule secondRule(Fact):
        what:
          (Alice, Color, c1)
          (otherPerson, Color, c2)
        cond:
          otherPerson != Alice.ord
        then:
          count += 1

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Alice, Color, "red")
  session.insert(Bob, Color, "blue")

  check count == 3

test "inserting inside a rule cascades":
  let rules =
    ruleset:
      rule firstRule(Fact):
        what:
          (b, Color, "blue")
        then:
          session.insert(Charlie, RightOf, Bob)
      rule secondRule(Fact):
        what:
          (c, RightOf, b)
        then:
          session.insert(b, LeftOf, c)
      rule thirdRule(Fact):
        what:
          (b, LeftOf, c)

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Bob, Color, "blue")

  check session.queryAll(rules.firstRule).len == 1
  check session.queryAll(rules.secondRule).len == 1
  check session.queryAll(rules.thirdRule).len == 1

test "conditions can use external values":
  var session = initSession(Fact)
  var allowRuleToFire = false
  let rule1 =
    rule rule1(Fact):
      what:
        (a, LeftOf, b)
      cond:
        allowRuleToFire
  session.add(rule1)

  session.insert(Alice, LeftOf, Zach)
  allowRuleToFire = true
  # this was causing an assertion error because
  # previously i assumed that all deletions
  # in leftActivation would succeed.
  session.insert(Alice, LeftOf, Bob)

  check session.queryAll(rule1).len == 1

  # now we prevent the rule from firing again,
  # but the old "Alice, LeftOf, Bob" fact
  # is still retractd successfully

  allowRuleToFire = false
  session.insert(Alice, LeftOf, Zach)

  check session.queryAll(rule1).len == 0

test "id + attr combos can be stored in multiple alpha nodes":
  let rules =
    ruleset:
      rule getAlice(Fact):
        what:
          (Alice, Color, color)
          (Alice, Height, height)
      rule getPerson(Fact):
        what:
          (id, Color, color)
          (id, Height, height)

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Alice, Color, "blue")
  session.insert(Alice, Height, 60)

  let alice = session.query(rules.getAlice)
  check alice.color == "blue"
  check alice.height == 60

  session.retract(Alice, Color, "blue")

  let index = session.find(rules.getAlice)
  check index == -1

test "IDs can be arbitrary integers":
  let zach = Id.high.ord + 1
  var session = initSession(Fact)
  let rule1 =
    rule rule1(Fact):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
        (z, LeftOf, b)
      then:
        check a == Alice
        check b == Bob
        check y == Yair
        check z == zach
  session.add(rule1)

  session.insert(Bob, Color, "blue")
  session.insert(Yair, LeftOf, zach)
  session.insert(Alice, Color, "maize")
  session.insert(Yair, RightOf, Bob)
  session.insert(zach, LeftOf, Bob)

  check session.queryAll(rule1).len == 1

test "join value with id":
  let rules =
    ruleset:
      rule rule1(Fact):
        what:
          (Bob, LeftOf, id)
          (id, Color, color)
          (id, Height, height)

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Alice, Color, "blue")
  session.insert(Alice, Height, 60)
  session.insert(Bob, LeftOf, Alice)

  session.insert(Charlie, Color, "green")
  session.insert(Charlie, Height, 72)
  session.insert(Bob, LeftOf, Charlie)

  check session.queryAll(rules.rule1).len == 1

test "multiple joins":
  let rules =
    ruleset:
      rule rule1(Fact):
        what:
          (id1, LeftOf, Bob)
          (id1, Color, color)
          (id1, Height, height)
          (id2, LeftOf, leftOf)
          (id2, Color, color2, then = false)
          (id2, Height, height2, then = false)
        cond:
          id2 != id1
        then:
          session.insert(id2, Color, "red")
          session.insert(id2, Height, 72)

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Alice, LeftOf, Bob)
  session.insert(Alice, Color, "blue")
  session.insert(Alice, Height, 60)
  session.insert(Bob, LeftOf, Charlie)
  session.insert(Bob, Color, "green")
  session.insert(Bob, Height, 70)

test "join followed by non-join":
  let rules =
    ruleset:
      rule rule1(Fact):
        what:
          (id1, LeftOf, Bob)
          (id1, Color, color)
          (id1, Height, height)
          (Bob, RightOf, a)

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Bob, RightOf, Alice)
  session.insert(Alice, LeftOf, Bob)
  session.insert(Alice, Color, "blue")
  session.insert(Alice, Height, 60)
  session.insert(Charlie, LeftOf, Bob)
  session.insert(Charlie, Color, "green")
  session.insert(Charlie, Height, 70)

  check session.queryAll(rules.rule1).len == 2

test "only last condition can fire":
  var count = 0
  let rules =
    ruleset:
      rule rule1(Fact):
        what:
          (id1, LeftOf, Bob, then = false)
          (id1, Color, color, then = false)
          (Alice, Height, height)
        then:
          count += 1

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Alice, Height, 60) # out of order
  session.insert(Alice, LeftOf, Bob)
  session.insert(Alice, Color, "blue")

  check count == 1

  session.retract(Alice, Height)
  session.retract(Alice, LeftOf)
  session.retract(Alice, Color)

  session.insert(Alice, Height, 60)
  session.insert(Alice, LeftOf, Bob)
  session.insert(Alice, Color, "blue")

  check count == 2

  session.insert(Alice, LeftOf, Bob)
  session.insert(Alice, Color, "blue")

  check count == 2

  session.insert(Alice, Height, 60)

  check count == 3

test "avoid unnecessary rule firings":
  var count = 0
  let getPerson =
    rule getPerson(Fact):
      what:
        (id, Color, color)
        (id, LeftOf, leftOf)
        (id, Height, height)
      then:
        count += 1

  var session = initSession(Fact, autoFire = false)
  session.add(getPerson)

  session.insert(Bob, Color, "blue")
  session.insert(Bob, LeftOf, Zach)
  session.insert(Bob, Height, 72)
  session.insert(Alice, Color, "blue")
  session.insert(Alice, LeftOf, Zach)
  session.insert(Alice, Height, 72)
  session.fireRules()

  session.insert(Alice, Color, "blue")
  session.fireRules()

  check count == 3

test "thenFinally":
  var triggerCount = 0
  var allPeople: People
  let rules =
    ruleset:
      rule getPerson(Fact):
        what:
          (id, Color, color)
          (id, LeftOf, leftOf)
          (id, Height, height)
        thenFinally:
          let people = session.queryAll(this)
          session.insert(Derived, AllPeople, people)
      rule allPeople(Fact):
        what:
          (Derived, AllPeople, people)
        then:
          allPeople = people
          triggerCount += 1

  var session = initSession(Fact, autoFire = false)
  for r in rules.fields:
    session.add(r)

  session.insert(Bob, Color, "blue")
  session.insert(Bob, LeftOf, Zach)
  session.insert(Bob, Height, 72)
  session.insert(Alice, Color, "blue")
  session.insert(Alice, LeftOf, Zach)
  session.insert(Alice, Height, 72)
  session.fireRules()

  check allPeople.len == 2
  check triggerCount == 1

  session.retract(Alice, Color)
  session.fireRules()

  check allPeople.len == 1
  check triggerCount == 2

type
  Id2 = enum
    Number,
  Attr2 = enum
    Any, IsPositive, Doubled, Combined,
  IntBoolTuple = (int, bool)

schema Fact2(Id2, Attr2):
  Any: int
  IsPositive: bool
  Doubled: int
  Combined: IntBoolTuple

# based on https://github.com/raquo/Airstream#frp-glitches
test "frp glitch":
  var output: seq[(int, bool)]
  let rules =
    ruleset:
      rule isPositive(Fact2):
        what:
          (Number, Any, anyNum)
        then:
          session.insert(Number, IsPositive, anyNum > 0)
      rule doubledNumbers(Fact2):
        what:
          (Number, Any, anyNum)
        then:
          session.insert(Number, Doubled, anyNum * 2)
      rule combined(Fact2):
        what:
          (Number, IsPositive, isPositive)
          (Number, Doubled, doubled)
        then:
          session.insert(Number, Combined, (doubled, isPositive))
      rule printCombined(Fact2):
        what:
          (Number, Combined, combined)
        then:
          output.add(combined)

  var session = initSession(Fact2)
  for r in rules.fields:
    session.add(r)

  session.insert(Number, Any, -1)
  session.insert(Number, Any, 1)

  check output == @[(-2, false), (2, true)]

test "non-deterministic behavior":
  var triggerCount = 0
  let rules =
    ruleset:
      rule rule1(Fact):
        what:
          (id, Color, "blue")
        then:
          triggerCount += 1
          session.insert(id, Color, "green")
      rule rule2(Fact):
        what:
          (id, Color, "blue")
        then:
          triggerCount += 1
      rule rule3(Fact):
        what:
          (id, Color, "blue")
        then:
          triggerCount += 1

  var session = initSession(Fact, autoFire = false)
  for r in rules.fields:
    session.add(r)

  session.insert(Bob, Color, "blue")
  session.fireRules()

  check triggerCount == 3

test "contains":
  let rules =
    ruleset:
      rule rule1(Fact):
        what:
          (id, Color, "blue")

  var session = initSession(Fact, autoFire = false)
  for r in rules.fields:
    session.add(r)

  session.insert(Bob, Color, "blue")
  check session.contains(Bob, Color)
  session.retract(Bob, Color)
  check not session.contains(Bob, Color)

  # can also pass id as an int
  check not session.contains(Bob.ord, Color)

test "two sessions can use the same rules":
  let rules =
    ruleset:
      rule getAlice(Fact):
        what:
          (Alice, Color, color)
          (Alice, Height, height)
      rule getPerson(Fact):
        what:
          (id, Color, color)
          (id, Height, height)

  var session = initSession(Fact)
  for r in rules.fields:
    session.add(r)

  session.insert(Alice, Color, "blue")
  session.insert(Alice, Height, 60)

  # second session uses the same rules but inserts different values
  var session2 = initSession(Fact)
  for r in rules.fields:
    session2.add(r)
  session2.insert(Alice, Color, "green")
  session2.insert(Alice, Height, 70)

  # first session returns the correct values
  let alice = session.query(rules.getAlice)
  check alice.color == "blue"
  check alice.height == 60

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
  AllPeople: People
