import pararules/engine, tables, sets, macros, strutils

proc isVar(node: NimNode): bool =
  node.kind == nnkIdent and node.strVal[0].isLowerAscii

proc wrapVar(node: NimNode): NimNode =
  if node.isVar:
    let s = node.strVal
    quote do:
      Var(name: `s`)
  else:
    node

proc createLet(ids: Table[string, int], paramNode: NimNode): NimNode =
  result = newStmtList()
  for s in ids.keys:
    result.add(newLetStmt(
      newIdentNode(s),
      quote do:
        `paramNode`[`s`]
    ))

proc getVarsInNode(node: NimNode): HashSet[string] =
  if node.isVar:
    result.incl(node.strVal)
  for child in node:
    result = result.union(child.getVarsInNode)

proc parseCond(ids: Table[string, int], node: NimNode): Table[int, NimNode] =
  expectKind(node, nnkStmtList)
  for condNode in node:
    var condNum = 0
    for ident in condNode.getVarsInNode:
      if ids.hasKey(ident):
        condNum = max(condNum, ids[ident])
    if result.hasKey(condNum):
      let prevCond = result[condNum]
      result[condNum] = quote do:
        `prevCond` and `condNode`
    else:
      result[condNum] = condNode

proc getUsedIds(ids: Table[string, int], node: NimNode): Table[string, int] =
  for v in node.getVarsInNode:
    if ids.hasKey(v):
      result[v] = ids[v]

proc addCond(dataType:NimNode, ids: Table[string, int], prod: NimNode, node: NimNode, filter: NimNode): NimNode =
  expectKind(node, nnkPar)
  let id = node[0].wrapVar
  let attr = node[1].wrapVar
  let value = node[2].wrapVar
  if filter != nil:
    let fn = genSym(nskLet, "fn")
    let v = genSym(nskParam, "v")
    let usedIds = getUsedIds(ids, filter)
    let letNode = createLet(usedIds, v)
    quote do:
      let `fn` = proc (`v`: Table[string, `dataType`]): bool =
        `letNode`
        `filter`
      addCondition(`prod`, `id`, `attr`, `value`, `fn`)
  else:
    quote do:
      addCondition(`prod`, `id`, `attr`, `value`)

proc parseWhat(dataType: NimNode, node: NimNode, condNode: NimNode, thenNode: NimNode): NimNode =
  var ids: Table[string, int]
  for condNum in 0 ..< node.len:
    let child = node[condNum]
    expectKind(child, nnkPar)
    for i in 0..2:
      if child[i].kind == nnkIdent:
        let s = child[i].strVal
        if not ids.hasKey(s):
          ids[s] = condNum

  expectKind(node, nnkStmtList)
  var conds: Table[int, NimNode]
  if condNode != nil:
    conds = parseCond(ids, condNode)

  let prod = genSym(nskVar, "prod")
  let v = genSym(nskParam, "v")

  if thenNode != nil:
    let usedIds = getUsedIds(ids, thenNode)
    let letNode = createLet(usedIds, v)
    result = newStmtList(quote do:
      var `prod` = newProduction[`dataType`](proc (`v`: Table[string, `dataType`]) =
        `letNode`
        `thenNode`
      )
    )
  else:
    result = newStmtList(quote do:
      var `prod` = newProduction[`dataType`](proc (`v`: Table[string, `dataType`]) = discard
      )
    )

  for condNum in 0 ..< node.len:
    let child = node[condNum]
    result.add addCond(datatype, ids, prod, child, if conds.hasKey(condNum): conds[condNum] else: nil)
  result.add prod

macro rule*(dataType: type, body: untyped): untyped =
  expectKind(body, nnkStmtList)
  result = newStmtList()
  var t: Table["string", NimNode]
  for child in body:
    expectKind(child, nnkCall)
    let id = child[0]
    expectKind(id, nnkIdent)
    t[id.strVal] = child[1]
  result.add parseWhat(
    dataType,
    t["what"],
    if t.hasKey("cond"): t["cond"] else: nil,
    if t.hasKey("then"): t["then"] else: nil
  )

proc parseSchemaPair(pair: NimNode): tuple[key: string, val: string] =
  expectKind(pair, nnkCall)
  let key = pair[0]
  expectKind(key, nnkIdent)
  var val = pair[1]
  expectKind(val, nnkStmtList)
  val = val[0]
  expectKind(val, nnkIdent)
  (key.strVal, val.strVal)

proc createBranch(key: string, val: string): NimNode =
  result = newNimNode(nnkOfBranch)
  var list = newNimNode(nnkRecList)
  list.add(newIdentDefs(ident(key), ident(val)))
  result.add(ident(key.capitalizeAscii), list)

proc createEnum(name: NimNode, pairs: Table[string, string]): NimNode =
  result = newNimNode(nnkTypeDef).add(
    newNimNode(nnkPragmaExpr).add(name).add(
      newNimNode(nnkPragma).add(ident("pure"))),
    newEmptyNode())
  var choices = newNimNode(nnkEnumTy).add(newEmptyNode())
  for name in pairs.keys():
    choices.add(ident(name.capitalizeAscii))
  result.add(choices)

proc createTypes(dataType: NimNode, enumName: NimNode, schemaPairs: Table[string, string]): NimNode =
  let enumType = createEnum(postfix(enumName, "*"), schemaPairs)
  var cases = newNimNode(nnkRecCase)
  cases.add(newIdentDefs(postfix(ident("kind"), "*"), enumName))
  for (key, val) in schemaPairs.pairs():
    cases.add(createBranch(key, val))

  result = newNimNode(nnkTypeSection)
  result.add(enumType)
  result.add(newNimNode(nnkTypeDef).add(
    postfix(dataType, "*"),
    newEmptyNode(), #newNimNode(nnkGenericParams),
    newNimNode(nnkObjectTy).add(
      newEmptyNode(),
      newEmptyNode(),
      newNimNode(nnkRecList).add(cases)
    )
  ))

proc createEqBranch(key: string): NimNode =
  let keyNode = ident(key)
  result = newNimNode(nnkOfBranch)
  let eq = infix(newDotExpr(ident("a"), keyNode), "==", newDotExpr(ident("b"), keyNode))
  let list = newStmtList(newNimNode(nnkReturnStmt).add(eq))
  result.add(ident(key.capitalizeAscii), list)

proc createEqProc(dataType: NimNode, enumName: NimNode, schemaPairs: Table[string, string]): NimNode =
  var cases = newNimNode(nnkCaseStmt).add(newDotExpr(ident("a"), ident("kind")))
  for key in schemaPairs.keys():
    cases.add(createEqBranch(key))

  let body = quote do:
    if a.kind == b.kind:
      `cases`
    else:
      return false

  result = newProc(
    name = postfix(ident("=="), "*"),
    params = [
      ident("bool"),
      newIdentDefs(ident("a"), dataType),
      newIdentDefs(ident("b"), dataType)
    ],
    body = newStmtList(body)
  )

macro schema*(dataType: untyped, body: untyped): untyped =
  expectKind(body, nnkStmtList)
  var schemaPairs: Table[string, string]
  for child in body:
    let (key, val) = parseSchemaPair(child)
    assert not schemaPairs.hasKey(key)
    schemaPairs[key] = val

  expectKind(dataType, nnkIdent)
  let enumName = ident(dataType.strVal & "Kind")
  newStmtList(
    createTypes(dataType, enumName, schemaPairs),
    createEqProc(dataType, enumName, schemaPairs)
  )
