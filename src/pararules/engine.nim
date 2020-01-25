import strformat, tables, algorithm

type
  # facts
  Field = enum
    Identifier, Attribute, Value
  Fact[T] = tuple[id: T, attr: T, value: T]
  Token[T] = tuple[fact: Fact[T], insert: bool]
  IdAttr = tuple[id: int, attr: int]
  Vars[T] = Table[string, T]
  Var* = object
    name*: string
    field: Field
  CallbackFn[T] = proc (vars: Vars[T])
  FilterFn[T] = proc (vars: Vars[T]): bool
  # alpha network
  AlphaNode[T] = ref object
    testField: Field
    testValue: T
    facts: Table[IdAttr, Fact[T]]
    successors: seq[JoinNode[T]]
    children: seq[AlphaNode[T]]
  # beta network
  MemoryNodeType = enum
    Root, Partial, Full
  MemoryNode[T] = ref object
    parent: JoinNode[T]
    children: seq[JoinNode[T]]
    vars: seq[Vars[T]]
    condition: Condition[T]
    case nodeType: MemoryNodeType
      of Full:
        callback: CallbackFn[T]
      else:
        nil
    when not defined(release):
      debugFacts*: seq[seq[Fact[T]]]
  JoinNode[T] = ref object
    parent: MemoryNode[T]
    children: seq[MemoryNode[T]]
    alphaNode: AlphaNode[T]
    condition: Condition[T]
  # session
  Condition[T] = object
    nodes: seq[AlphaNode[T]]
    vars: seq[Var]
    filter: FilterFn[T]
  Production[T] = object
    conditions: seq[Condition[T]]
    callback: CallbackFn[T]
  Session[T] = object
    alphaNode: AlphaNode[T]
    betaNode: MemoryNode[T]
    allFacts: Table[IdAttr, Fact[T]]

proc getParent*(node: MemoryNode): MemoryNode =
  node.parent.parent

proc addNode(node: AlphaNode, newNode: AlphaNode): AlphaNode =
  for child in node.children:
    if child.testField == newNode.testField and child.testValue == newNode.testValue:
      return child
  node.children.add(newNode)
  return newNode

proc addNodes(session: Session, nodes: seq[AlphaNode]): AlphaNode =
  result = session.alphaNode
  for node in nodes:
    result = result.addNode(node)

proc addCondition*[T](production: var Production[T], id: Var or T, attr: Var or T, value: Var or T, filter: FilterFn[T] = nil) =
  var condition = Condition[T](filter: filter)
  for fieldType in [Field.Identifier, Field.Attribute, Field.Value]:
    case fieldType:
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

proc isAncestor(x, y: JoinNode): bool =
  var node = y
  while node != nil and node.parent != nil:
    if node.parent.parent == x:
      return true
    else:
      node = node.parent.parent
  false

proc addProduction*[T](session: Session[T], production: Production[T]): MemoryNode[T] =
  result = session.betaNode
  let last = production.conditions.len - 1
  for i in 0 .. last:
    var condition = production.conditions[i]
    var leafNode = session.addNodes(condition.nodes)
    var joinNode = JoinNode[T](parent: result, alphaNode: leafNode, condition: condition)
    result.children.add(joinNode)
    leafNode.successors.add(joinNode)
    # successors must be sorted by ancestry (descendents first) to avoid duplicate rule firings
    leafNode.successors.sort(proc (x, y: JoinNode[T]): int =
      if isAncestor(x, y): 1 else: -1)
    var newMemNode = MemoryNode[T](parent: joinNode, nodeType: if i == last: Full else: Partial, condition: condition)
    if newMemNode.nodeType == Full:
      newMemNode.callback = production.callback
    joinNode.children.add(newMemNode)
    result = newMemNode

proc getVarsFromFact[T](vars: var Vars[T], condition: Condition[T], fact: Fact[T]): bool =
  for v in condition.vars:
    case v.field:
      of Identifier:
        if vars.hasKey(v.name) and vars[v.name] != fact[0]:
          return false
        else:
          vars[v.name] = fact[0]
      of Attribute:
        if vars.hasKey(v.name) and vars[v.name] != fact[1]:
          return false
        else:
          vars[v.name] = fact[1]
      of Value:
        if vars.hasKey(v.name) and vars[v.name] != fact[2]:
          return false
        else:
          vars[v.name] = fact[2]
  true

proc performJoinTests(node: JoinNode, vars: Vars, alphaFact: Fact): bool =
  var newVars = vars
  if not newVars.getVarsFromFact(node.condition, alphaFact):
    return false
  if node.condition.filter != nil:
    if not node.condition.filter(newVars):
      return false
  true

proc leftActivation[T](node: MemoryNode[T], vars: Vars[T], debugFacts: seq[Fact[T]], token: Token[T])

proc leftActivation[T](node: JoinNode[T], vars: Vars[T], debugFacts: seq[Fact[T]], insert: bool) =
  for alphaFact in node.alphaNode.facts.values:
    if performJoinTests(node, vars, alphaFact):
      for child in node.children:
        child.leftActivation(vars, debugFacts, (alphaFact, insert))

proc leftActivation[T](node: MemoryNode[T], vars: Vars[T], debugFacts: seq[Fact[T]], token: Token[T]) =
  var newVars = vars
  let success = newVars.getVarsFromFact(node.condition, token.fact)
  assert success

  when not defined(release):
    var debugFacts = debugFacts
    debugFacts.add(token.fact)

  if token.insert:
    node.vars.add(newVars)
    when not defined(release):
      node.debugFacts.add(debugFacts)
  else:
    let index = node.vars.find(newVars)
    assert index >= 0
    node.vars.delete(index)
    when not defined(release):
      node.debugFacts.delete(index)

  if node.nodeType == Full and token.insert:
    node.callback(newVars)
  else:
    for child in node.children:
      child.leftActivation(newVars, debugFacts, token.insert)

proc rightActivation[T](node: JoinNode[T], token: Token[T]) =
  if node.parent.nodeType == Root:
    for child in node.children:
      child.leftActivation(initTable[string, T](), newSeq[Fact[T]](), token)
  else:
    for i in 0 ..< node.parent.vars.len:
      let vars = node.parent.vars[i]
      let debugFacts =
        when not defined(release):
          node.parent.debugFacts[i]
        else:
          newSeq[Fact[T]]()
      if performJoinTests(node, vars, token.fact):
        for child in node.children:
          child.leftActivation(vars, debugFacts, token)

proc rightActivation[T](node: AlphaNode[T], token: Token[T]) =
  let id = token.fact.id.idVal.ord
  let attr = token.fact.attr.attrVal.ord
  if token.insert:
    node.facts[(id, attr)] = token.fact
  else:
    node.facts.del((id, attr))
  for child in node.successors:
    child.rightActivation(token)

proc addFact(node: AlphaNode, fact: Fact, root: bool, insert: bool): bool =
  if not root:
    let val = case node.testField:
      of Field.Identifier: fact[0]
      of Field.Attribute: fact[1]
      of Field.Value: fact[2]
    if val != node.testValue:
      return false
  for child in node.children:
    if child.addFact(fact, false, insert):
      return true
  node.rightActivation((fact, insert))
  true

proc addFact*[T](session: var Session[T], fact: Fact[T]) =
  let id = fact.id.idVal.ord
  let attr = fact.attr.attrVal.ord
  let idAttr = (id, attr)
  if session.allFacts.hasKey(idAttr):
    session.removeFact(session.allFacts[idAttr])
  session.allFacts[idAttr] = fact
  discard session.alphaNode.addFact(fact, true, true)

proc removeFact*[T](session: Session[T], fact: Fact[T]) =
  discard session.alphaNode.addFact(fact, true, false)

proc newSession*[T](): Session[T] =
  result.alphaNode = new(AlphaNode[T])
  result.betaNode = new(MemoryNode[T])

proc newProduction*[T](cb: CallbackFn[T]): Production[T] =
  result.callback = cb

proc print(fact: Fact, indent: int): string
proc print[T](node: JoinNode[T], indent: int): string
proc print[T](node: MemoryNode[T], indent: int): string
proc print(node: AlphaNode, indent: int): string

proc print(fact: Fact, indent: int): string =
  if indent >= 0:
    for i in 0 ..< indent:
      result &= "  "
  result &= "Fact = {fact} \n".fmt

proc print[T](node: JoinNode[T], indent: int): string =
  for i in 0 ..< indent:
    result &= "  "
  result &= "JoinNode\n"
  for child in node.children:
    result &= print(child, indent+1)

proc print[T](node: MemoryNode[T], indent: int): string =
  for i in 0 ..< indent:
    result &= "  "
  let cnt = node.vars.len
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
    result &= "{node.testField} = {node.testValue} ({cnt})\n".fmt
  for fact in node.facts:
    result &= print(fact, indent+1)
  for child in node.children:
    result &= print(child, indent+1)

proc `$`*(session: Session): string =
  var alphaNode = session.alphaNode
  print(alphaNode, 0) & print(session.betaNode, 0)
