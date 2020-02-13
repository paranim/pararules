Pararules is the first RETE-based rules engine made for games. It may also be the last, if this turns out to be a bad idea.

Rules engines have been around since the 70s, and the RETE algorithm has been used for almost that long. For some reason, they haven't found their way into games yet. With pararules, you can store the entire state of your game and express the logic as a simple series of rules.

## Start with the data

Your data is stored as `(id, attribute, value)` tuples. For example, the player's X position might be `(Player, X, 100.0)`. The delta time (which is the number of seconds since the last frame) might be `(Global, DeltaTime, 0.0168121)`.

To do this, you need to first define your id and attribute enums, like this:

```nim
type
  Id = enum
    Global, Player,
  Attr = enum
    DeltaTime, TotalTime,
    X, Y,
```

Then, you use the `schema` macro, which receives these two enums and defines what type the value will have for each attribute:

```nim
schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  X: float
  Y: float
```

Underneath, this creates a new type called `Fact` which in Nim is called an *object variant* because it can store multiple types inside.

## Your first rule

Let's start by just making a rule that prints out the `TotalTime` whenever it updates:

```nim
# create rule
let rule1 =
  rule printTime(Fact):
    what:
      (Global, TotalTime, tt)
    then:
      echo tt

# create session and add rule
var session = initSession(Fact)
session.add(rule1)
```

The most important part of a rule is the `what` block, which specifies what tuples must exist for the rule to fire. The key is that you can create a *binding* in the id or value column by supplying a symbol that starts with a lowercase letter, like `tt` above. When the rule fires, the `then` block is executed, which has access to the bindings you created.

In your game loop, you can then insert the time values:

```nim
session.insert(Global, DeltaTime, game.deltaTime)
session.insert(Global, TotalTime, game.totalTime)
```

The nice thing is that, if you insert something whose id + attribute combo already exists, it will simply replace it. So you can safely insert these values in your game loop without worrying that it will fill up with stale data.

## Updating the session from inside a rule

Now imagine you want to make the player move to the right every time the frame is redrawn. Your rule might look like this:

```nim
let rule1 =
  rule movePlayer(Fact):
    what:
      (Global, TotalTime, tt)
    then:
      session.insert(Player, X, tt)

var session = initSession(Fact)
session.add(rule1)
```

This may look weird, because `session` is defined *after* the rule, but somehow the rule can still use it. This is because `then` blocks have an implicit `session` variable, which refers to whatever session the rule is part of. You should always use this when updating the session from within a rule.

## Queries

Updating the player's `X` attribute isn't useful unless we can get the value externally to render it. To do this, make another rule that binds the values you would like to receive:

```nim
let rule2 =
  rule getPlayer(Fact):
    what:
      (Player, X, x)
      (Player, Y, y)

session.add(rule2)
``` 

As you can see, rules don't need a `then` block if you're only using them to query from the outside. In this case, we'll query it in our game loop and we'll get back a tuple whose fields have the names you created as bindings:

```nim
let player = session.query(rule2)
echo player.x, " ", player.y
```

Be careful with `query`, though. If the facts in the rule's `what` block haven't been inserted yet, you'll get an exception. If you are unsure if the facts are there, you should use `find` + `get` instead:

```nim
let index = session.find(rule2)
if index >= 0:
  let player = session.get(rule2, index)
  echo player.x, " ", player.y
```

## Rulesets

As a convenience, you can define your rules together like this:

```nim
let rules =
  ruleset:
    rule movePlayer(Fact):
      what:
        (Global, TotalTime, tt)
      then:
        session.insert(Player, X, tt)
    rule getPlayer(Fact):
      what:
        (Player, X, x)
        (Player, Y, y)
```

Then you can add them to a session all at once:

```nim
for r in rules.fields:
  session.add(r)
```

The `rules` value is a tuple whose fields have the same names as the rules' names. This makes it nice to run queries:

```nim
let player = session.query(rules.getPlayer)
echo player.x, " ", player.y
```

## Avoiding infinite loops

Imagine you want to move the player's position based on its current position. So instead of just using the total time, maybe we want to add the delta time to the player's latest `X` position. If you try this, you might hear your computer's fan get louder:

```nim
rule movePlayer(Fact):
  what:
    (Global, DeltaTime, dt)
    (Player, X, x)
  then:
    session.insert(Player, X, x + dt)
```

That's because you just created an infinite loop. The rule requires the player's `X` position and then updates it, which then causes the rule to fire again. The simple solution is to tell pararules that a certain tuple should not cause a rule's `then` block to re-fire when it updates:

```nim
rule movePlayer(Fact):
  what:
    (Global, DeltaTime, dt)
    (Player, X, x, then = false)
  then:
    session.insert(Player, X, x + dt)
```

## Conditions

Rules have nice a way of breaking apart your logic into independent units. If we want to prevent the player from moving off the right side of the screen, we could add a condition inside of the `then` block of `movePlayer`, but it's good to get in the habit of making separate rules.

To do so, we need to start storing the window size in the session. First, add the attributes:

```nim
type
  Id = enum
    Global, Player,
  Attr = enum
    DeltaTime, TotalTime,
    X, Y,
    WindowWidth, WindowHeight,

schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  X: float
  Y: float
  WindowWidth: int
  WindowHeight: int
```

Then, wherever your window resize happens, insert the values:

```nim
proc windowResized*(width: int, height: int) =
  session.insert(Global, WindowWidth, width)
  session.insert(Global, WindowHeight, height)
```

Finally, we make the rule:

```nim
rule stopPlayer(Fact):
  what:
    (Player, X, x)
    (Global, WindowWidth, windowWidth)
  then:
    if x >= float(windowWidth):
      session.insert(Player, X, 0.0)
```

Notice that we *don't* need `then = false` this time, because the condition is preventing the rule from re-firing (unless the `windowWidth` is 0, that is!).

While the above code works, it is not ideal. If you have a condition like the one above, it is better to place it in a special `cond` block:

```nim
rule stopPlayer(Fact):
  what:
    (Global, WindowWidth, windowWidth)
    (Player, X, x)
  cond:
    x >= float(windowWidth)
  then:
    session.insert(Player, X, 0.0)
```

Not only does this read more nicely, it may actually be faster. This is because, by specifying the condition there, pararules can run the condition earlier, rather than wait until all facts are matched and the `then` block is fired.

You can add as many conditions as you want, and they will implicitly work as if they were combined together with `and`:

```nim
rule stopPlayer(Fact):
  what:
    (Global, WindowWidth, windowWidth)
    (Player, X, x)
  cond:
    x >= float(windowWidth)
    windowWidth > 0
  then:
    session.insert(Player, X, 0.0)
```

It is better to do it that way than to write `x >= float(windowWidth) and windowWidth > 0` on one line, because it gives pararules the opportunity to run each condition at the optimal time. If you need the conditions to work with an `or`, though, you will need to put them together in that way.

## Complex types

Pararules is not limited to storing scalar types like `float` and `int` — you can use any type you want. For example, to store the currently-pressed keys, you can import the `sets` module and use a `HashSet[int]` to store them. However, you need to use a type alias when specifying it in the schema:

```nim
type
  Id = enum
    Global, Player,
  Attr = enum
    DeltaTime, TotalTime,
    X, Y,
    WindowWidth, WindowHeight,
    PressedKeys,
  IntSet = HashSet[int]

schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  X: float
  Y: float
  WindowWidth: int
  WindowHeight: int
  PressedKeys: IntSet
```

If you put `HashSet[int]` directly in the `schema` macro, it will fail, because it wants a simple name to refer to it by. Also note that if you create two type aliases that point to the same type, the schema macro will complain...so don't do that. These are just implementation restrictions right now.

When you initialize your game, you can put an empty set in it:

```nim
session.insert(Global, PressedKeys, initHashSet[int]())
```

Then add a rule to get the keys:

```nim
rule getKeys(Fact):
  what:
    (Global, PressedKeys, keys)
```

Wherever your key up/down events are, you can update the keys:

```nim
proc keyPressed*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.incl(key)
  session.insert(Global, PressedKeys, keys)

proc keyReleased*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.excl(key)
  session.insert(Global, PressedKeys, keys)
```

You can see we are destructuring the `keys` out of the tuple, modifying it, and then updating `PressedKeys` with it. Now we can modify `movePlayer` to change the player's `X` position based on the arrow keys:

```nim
rule movePlayer(Fact):
  what:
    (Global, DeltaTime, dt)
    (Global, PressedKeys, keys, then = false)
    (Player, X, x, then = false)
  then:
    if keys.contains(263): # left arrow
      session.insert(Player, X, x - 1.0)
    elif keys.contains(262): # right arrow
      session.insert(Player, X, x + 1.0)
```

Notice that we aren't even using `DeltaTime` anymore, but we're keeping it in the `what` block so the rule continues to fire every frame. If all tuples in the `what` block have `then = false`, it will never fire. This way, it will move the player exactly one pixel each frame that an arrow key is pressed. Not exactly the best way to do character movement, but you get the idea.

## Wrap up

In a way, rules engines just give you a fancy `if` statement. You tell it what data it needs, what conditions the data must meet, and what should happen when it does. The real power is that they let you express your game's logic as independent units, each one explicitly stating what they need in order to run. That lets you reason about them in isolation.

## Comparison to Clara Rules

I was inspired a lot by [Clara Rules](https://github.com/cerner/clara-rules), a rules engine for Clojure. Right now pararules has advantages and disadvantages compared to it.

Advantages compared to Clara:

* Pararules stores data in `(id, attribute, value)` tuples, whereas Clara uses Clojure records. I think storing each key-value pair as a separate fact leads to a much more flexible system. Technically you could make Clara work this way, but records tend to encourage you to combine data together.
* Pararules has built-in support for updating facts. You don't even need to explicitly do it; simply inserting a fact with an existing id + attribute combo will cause the old fact to be removed. This is only possible because of the aforementioned use of tuples.
* Pararules provides a simple `rule` macro that returns an object that can be added to any (or even multiple) sessions. Clara's `defrule` macro creates a global var that is implicitly added to a session. I tried to solve that particular problem with my [clarax](https://github.com/oakes/clarax) library but with pararules it's even cleaner because each rule is completely separate and can be added to a session independently.

Disadvantages compared to Clara:

* Clara supports [truth maintenance](https://www.clara-rules.org/docs/truthmaint/), which can be a very useful feature in some domains. I don't plan on supporting this in pararules because I'm not convinced it's that useful for game dev.
* Clara supports [accumulators](https://www.clara-rules.org/docs/accumulators/) for gathering multiple facts together for use in a rule. I'm not sure if I want to support something like this yet.
* Clara's sessions are completely immutable data structures. This makes it really simple to hold on to old versions of a session, in order to implement time rewinding or as a useful debugging tool. I want to implement this in pararules eventually.
* Clara's sessions can be serialized and deserialized. I'd like to support this too.

## Acknowledgements

I could not have built this without the [1995 thesis paper from Robert Doorenbos](http://reports-archive.adm.cs.cmu.edu/anon/1995/CMU-CS-95-113.pdf), which describes the RETE algorithm better than I've found anywhere else. I also stole a lot of design ideas from [Clara Rules](https://github.com/cerner/clara-rules).
