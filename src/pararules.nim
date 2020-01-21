import strformat, tables, algorithm

type
  # facts
  Field = enum
    Identifier, Attribute, Value
  Fact[I, A, V] = tuple[id: I, attr: A, value: V]
  # alpha network
  AlphaNode[I, A, V] = ref object
    case field: Field
    of Identifier:
      id: I
    of Attribute:
      attr: A
    of Value:
      value: V
    facts: seq[Fact[I, A, V]]
    successors: seq[JoinNode[I, A, V]]
    children: seq[AlphaNode[I, A, V]]
  # beta network
  TestAtJoinNode = object
    alphaField: Field
    betaField: Field
    condition: int
  NodeType = enum
    Root, Partial, Full
  MemoryNode[I, A, V] = ref object
    parent: JoinNode[I, A, V]
    children: seq[JoinNode[I, A, V]]
    facts*: seq[seq[Fact[I, A, V]]]
    case nodeType: NodeType
    of Full:
      production: Production[I, A, V]
    else:
      nil
  JoinNode[I, A, V] = ref object
    parent: MemoryNode[I, A, V]
    children: seq[MemoryNode[I, A, V]]
    alphaNode: AlphaNode[I, A, V]
    tests: seq[TestAtJoinNode]
  # session
  Vars[T] = Table[string, T]
  Var* = object
    name*: string
    field: Field
  Condition[I, A, V] = object
    nodes: seq[AlphaNode[I, A, V]]
    vars: seq[Var]
  Callback[I, A, V] = proc (ids: Vars[I], attrs: Vars[A], values: Vars[V])
  Production[I, A, V] = object
    conditions: seq[Condition[I, A, V]]
    callback: Callback[I, A, V]
  Session[I, A, V] = object
    alphaNode: AlphaNode[I, A, V]
    betaNode: MemoryNode[I, A, V]

proc `==`(x, y: AlphaNode): bool =
  x.field == y.field and
    (case x.field:
     of Identifier: x.id == y.id
     of Attribute: x.attr == y.attr
     of Value: x.value == y.value)

proc addNode(node: AlphaNode, newNode: AlphaNode): AlphaNode =
  for child in node.children:
    if child == newNode:
      return child
  node.children.add(newNode)
  return newNode

proc addNodes(session: Session, nodes: seq[AlphaNode]): AlphaNode =
  result = session.alphaNode
  for node in nodes:
    result = result.addNode(node)

proc newIdAlphaNode[I, A, V](id: I): AlphaNode[I, A, V] =
  AlphaNode[I, A, V](field: Identifier, id: id)

proc newAttrAlphaNode[I, A, V](attr: A): AlphaNode[I, A, V] =
  AlphaNode[I, A, V](field: Attribute, attr: attr)

proc newValueAlphaNode[I, A, V](value: V): AlphaNode[I, A, V] =
  AlphaNode[I, A, V](field: Value, value: value)

proc addCondition*[I, A, V](production: var Production[I, A, V], id: Var or I, attr: Var or A, value: Var or V) =
  var condition = Condition[I, A, V]()
  for fieldType in [Field.Identifier, Field.Attribute, Field.Value]:
    case fieldType:
      of Field.Identifier:
        when id is I:
          condition.nodes.add(newIdAlphaNode[I, A, V](id))
        else:
          var temp = id
          temp.field = fieldType
          condition.vars.add(temp)
      of Field.Attribute:
        when attr is A:
          condition.nodes.add(newAttrAlphaNode[I, A, V](attr))
        else:
          var temp = attr
          temp.field = fieldType
          condition.vars.add(temp)
      of Field.Value:
        when value is V:
          condition.nodes.add(newValueAlphaNode[I, A, V](value))
        else:
          var temp = value
          temp.field = fieldType
          condition.vars.add(temp)
  production.conditions.add(condition)

proc isAncestor(x, y: JoinNode): bool =
  var node = y
  while node != nil and node.parent != nil:
    if node.parent.parent == x:
      return true
    else:
      node = node.parent.parent
  false

proc addProduction*[I, A, V](session: Session[I, A, V], production: Production[I, A, V]): MemoryNode[I, A, V] =
  var joins: Table[string, (Var, int)]
  result = session.betaNode
  let last = production.conditions.len - 1
  for i in 0 .. last:
    var condition = production.conditions[i]
    var leafNode = session.addNodes(condition.nodes)
    var joinNode = JoinNode[I, A, V](parent: result, alphaNode: leafNode)
    for v in condition.vars:
      if joins.hasKey(v.name):
        let (joinVar, condNum) = joins[v.name]
        joinNode.tests.add(TestAtJoinNode(alphaField: v.field, betaField: joinVar.field, condition: condNum))
      joins[v.name] = (v, i)
    result.children.add(joinNode)
    leafNode.successors.add(joinNode)
    # successors must be sorted by ancestry (descendents first) to avoid duplicate rule firings
    leafNode.successors.sort(proc (x, y: JoinNode[I, A, V]): int =
      if isAncestor(x, y): 1 else: -1)
    var newMemNode = MemoryNode[I, A, V](parent: joinNode, nodeType: if i == last: Full else: Partial)
    if newMemNode.nodeType == Full:
      newMemNode.production = production
    joinNode.children.add(newMemNode)
    result = newMemNode

proc performJoinTest(test: TestAtJoinNode, alphaFact: Fact, betaFact: Fact): bool =
  let (alphaId, alphaAttr, alphaValue) = alphaFact
  let (betaId, betaAttr, betaValue) = betaFact
  case test.alphaField:
    of Identifier:
      case test.betaField:
        of Identifier:
          alphaId == betaId
        of Attribute:
          when alphaId is betaAttr.type:
            alphaId == betaAttr
          else:
            false
        of Value:
          alphaId == betaValue
    of Attribute:
      case test.betaField:
        of Identifier:
          when alphaAttr is betaId.type:
            alphaAttr == betaId
          else:
            false
        of Attribute:
          alphaAttr == betaAttr
        of Value:
          when alphaAttr is betaValue.type:
            alphaAttr == betaValue
          else:
            false
    of Value:
      case test.betaField:
        of Identifier:
          when alphaValue is betaId.type:
            alphaValue == betaId
          else:
            false
        of Attribute:
          when alphaValue is betaAttr.type:
            alphaValue == betaAttr
          else:
            false
        of Value:
          alphaValue == betaValue

proc performJoinTests(tests: seq[TestAtJoinNode], facts: seq[Fact], alphaFact: Fact): bool =
  for test in tests:
    let betaFact = facts[test.condition]
    if not performJoinTest(test, alphaFact, betaFact):
      return false
  true

proc leftActivation[I, A, V](node: MemoryNode[I, A, V], facts: seq[Fact[I, A, V]], fact: Fact[I, A, V])

proc leftActivation[I, A, V](node: JoinNode[I, A, V], facts: seq[Fact[I, A, V]]) =
  for alphaFact in node.alphaNode.facts:
    if performJoinTests(node.tests, facts, alphaFact):
      for child in node.children:
        child.leftActivation(facts, alphaFact)

proc leftActivation[I, A, V](node: MemoryNode[I, A, V], facts: seq[Fact[I, A, V]], fact: Fact[I, A, V]) =
  var newFacts = facts
  newFacts.add(fact)
  node.facts.add(newFacts)
  if node.nodeType == Full:
    assert node.production.conditions.len == newFacts.len
    var ids: Vars[I]
    var attrs: Vars[A]
    var values: Vars[V]
    for i in 0 ..< node.production.conditions.len:
      for v in node.production.conditions[i].vars:
        case v.field:
          of Identifier:
            if ids.hasKey(v.name):
              assert ids[v.name] == newFacts[i][0]
            else:
              ids[v.name] = newFacts[i][0]
          of Attribute:
            if attrs.hasKey(v.name):
              assert attrs[v.name] == newFacts[i][1]
            else:
              attrs[v.name] = newFacts[i][1]
          of Value:
            if values.hasKey(v.name):
              assert values[v.name] == newFacts[i][2]
            else:
              values[v.name] = newFacts[i][2]
    node.production.callback(ids, attrs, values)
  else:
    for child in node.children:
      child.leftActivation(newFacts)

proc rightActivation[I, A, V](node: JoinNode[I, A, V], fact: Fact[I, A, V]) =
  if node.parent.nodeType == Root:
    for child in node.children:
      child.leftActivation(@[], fact)
  else:
    for facts in node.parent.facts:
      if performJoinTests(node.tests, facts, fact):
        for child in node.children:
          child.leftActivation(facts, fact)

proc rightActivation(node: AlphaNode, fact: Fact) =
  node.facts.add(fact)
  for child in node.successors:
    child.rightActivation(fact)

proc addFact[I, A, V](node: AlphaNode, id: I, attr: A, value: V, root: bool): bool =
  if not root:
    let match = case node.field:
      of Field.Identifier: id == node.id
      of Field.Attribute: attr == node.attr
      of Field.Value: value == node.value
    if not match:
      return false
  for child in node.children:
    if child.addFact(id, attr, value, false):
      return true
  let fact = (id, attr, value)
  node.rightActivation(fact)
  true

proc addFact*[I, A, V](session: Session, id: I, attr: A, value: V) =
  discard session.alphaNode.addFact(id, attr, value, true)

proc newSession*[I, A, V](): Session[I, A, V] =
  result.alphaNode = new(AlphaNode[I, A, V])
  result.betaNode = new(MemoryNode[I, A, V])

proc newProduction*[I, A, V](cb: Callback[I, A, V]): Production[I, A, V] =
  result.callback = cb

proc print(fact: Fact, indent: int): string
proc print[I, A, V](node: JoinNode[I, A, V], indent: int): string
proc print[I, A, V](node: MemoryNode[I, A, V], indent: int): string
proc print(node: AlphaNode, indent: int): string

proc print(fact: Fact, indent: int): string =
  if indent >= 0:
    for i in 0 ..< indent:
      result &= "  "
  result &= "Fact = {fact} \n".fmt

proc print[I, A, V](node: JoinNode[I, A, V], indent: int): string =
  for i in 0 ..< indent:
    result &= "  "
  result &= "JoinNode\n"
  for child in node.children:
    result &= print(child, indent+1)

proc print[I, A, V](node: MemoryNode[I, A, V], indent: int): string =
  for i in 0 ..< indent:
    result &= "  "
  let cnt = node.facts.len
  if node.nodeType == Full:
    result &= "ProdNode ({cnt})\n".fmt
  else:
    result &= "MemoryNode ({cnt})\n".fmt
  for child in node.children:
    result &= print(child, indent+1)

proc print(node: AlphaNode, indent: int): string =
  let cnt = node.successors.len
  if indent == 0:
    result &= "AlphaNode ({cnt})\n".fmt
  else:
    for i in 0 ..< indent:
      result &= "  "
    result &= "{node.field} ({cnt})\n".fmt
  for fact in node.facts:
    result &= print(fact, indent+1)
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  var alphaNode = session.alphaNode
  print(alphaNode, 0) & print(session.betaNode, 0)
