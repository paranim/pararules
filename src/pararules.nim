import strformat, tables

type
  # alpha network
  Field = enum
    None, Identifier, Attribute, Value
  Fact[T] = tuple[id: T, attr: T, value: T]
  AlphaNode[T] = ref object
    testField: Field
    testValue: T
    facts: seq[Fact[T]]
    successors: seq[JoinNode[T]]
    children: seq[AlphaNode[T]]
  # beta network
  TestAtJoinNode = object
    alphaField: Field
    betaField: Field
  Token[T] = object
    alphaNode: AlphaNode[T]
    fact: Fact[T]
  BetaNode[T] = ref object of RootObj
    children: seq[BetaNode[T]]
    parent: BetaNode[T]
    varName: string
  MemoryNode[T] = ref object of BetaNode[T]
    tokens: seq[Token[T]]
  JoinNode[T] = ref object of BetaNode[T]
    alphaNode: AlphaNode[T]
    tests: seq[TestAtJoinNode]
  ProdNode[T] = ref object of BetaNode[T]
  # session
  Var* = object
    name*: string
    field: Field
  Condition[T] = object
    nodes: seq[AlphaNode[T]]
    vars: seq[Var]
  Production[T] = object
    conditions: seq[Condition[T]]
  Session[T] = object
    alphaNode: AlphaNode[T]
    betaNode: MemoryNode[T]

proc addNode(node: var AlphaNode, newNode: AlphaNode): AlphaNode =
  for child in node.children:
    if child.testField == newNode.testField and child.testValue == newNode.testValue:
      return child
  node.children.add(newNode)
  return newNode

proc addNodes(session: var Session, nodes: seq[AlphaNode]): AlphaNode =
  result = session.alphaNode
  for node in nodes:
    result = result.addNode(node)

proc addCondition*[T](production: var Production[T], id: Var or T, attr: Var or T, value: Var or T) =
  var condition = Condition[T]()
  for fieldType in [Field.Identifier, Field.Attribute, Field.Value]:
    case fieldType:
      of Field.None:
        continue
      of Field.Identifier:
        when id is T:
          condition.nodes.add AlphaNode[T](testField: fieldType, testValue: id)
        else:
          var temp = id
          temp.field = fieldType
          condition.vars.add(temp)
      of Field.Attribute:
        when attr is T:
          condition.nodes.add AlphaNode[T](testField: fieldType, testValue: attr)
        else:
          var temp = attr
          temp.field = fieldType
          condition.vars.add(temp)
      of Field.Value:
        when value is T:
          condition.nodes.add AlphaNode[T](testField: fieldType, testValue: value)
        else:
          var temp = value
          temp.field = fieldType
          condition.vars.add(temp)
  production.conditions.add(condition)

proc addProduction*[T](session: var Session[T], production: Production[T]) =
  var joins: Table[string, MemoryNode[T]]
  for condition in production.conditions:
    var leafNode = session.addNodes(condition.nodes)
    for v in condition.vars:
      let s = v.name
      if not joins.hasKey(s):
        var joinNode = JoinNode[T](parent: session.betaNode, alphaNode: leafNode, varName: s)
        leafNode.successors.add(joinNode)
        session.betaNode.children.add(joinNode)
        var newBetaNode = MemoryNode[T](parent: joinNode)
        joinNode.children.add(newBetaNode)
        joins[s] = newBetaNode
      else:
        var betaNode = joins[s]
        var joinNode = JoinNode[T](parent: betaNode, alphaNode: leafNode, varName: s)
        leafNode.successors.add(joinNode)
        betaNode.children.add(joinNode)
        var newBetaNode = MemoryNode[T](parent: joinNode)
        joinNode.children.add(newBetaNode)
        joins[s] = newBetaNode
  var pNode = ProdNode[T]()
  for betaNode in joins.mvalues():
    if not (pNode in betaNode.children):
      betaNode.children.add(pNode)

proc rightActivation(node: var JoinNode, fact: Fact) =
  echo fact

proc alphaMemoryRightActivation(node: var AlphaNode, fact: Fact) =
  node.facts.add(fact)
  for child in node.successors.mitems():
    child.rightActivation(fact)

proc addFact(node: var AlphaNode, fact: Fact) =
  let val = case node.testField:
    of Field.None: node.testValue
    of Field.Identifier: fact[0]
    of Field.Attribute: fact[1]
    of Field.Value: fact[2]
  if val != node.testValue:
    return
  elif node.testField != Field.None:
    node.alphaMemoryRightActivation(fact)
  for child in node.children.mitems():
    child.addFact(fact)

proc addFact*(session: var Session, fact: Fact) =
  session.alphaNode.addFact(fact)

proc newSession*[T](): Session[T] =
  result.alphaNode = new(AlphaNode[T])
  result.betaNode = new(MemoryNode[T])

proc newProduction*[T](): Production[T] =
  result

proc print(fact: Fact, indent: int): string =
  if indent >= 0:
    for i in 0 ..< indent:
      result &= "  "
  result &= "Fact = {fact} \n".fmt

proc print[T](node: BetaNode[T], indent: int): string =
  for i in 0 ..< indent:
    result &= "  "
  if node of MemoryNode[T]:
    result &= "MemoryNode\n"
  elif node of JoinNode[T]:
    result &= "JoinNode {node.varName}\n".fmt
  elif node of ProdNode[T]:
    result &= "ProdNode\n"
  for child in node.children:
    result &= print(child, indent+1)

proc print(node: AlphaNode, indent: int): string =
  if indent == 0:
    result &= "AlphaNode\n"
  else:
    for i in 0 ..< indent:
      result &= "  "
    result &= "{node.testField} = {node.testValue}\n".fmt
    if node.successors.len > 0:
      for s in node.successors:
        result &= print(s, indent+1)
  for fact in node.facts:
    result &= print(fact, indent+1)
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  print(session.alphaNode, 0) & print(session.betaNode, 0)
