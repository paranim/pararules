import pararules/engine, tables, sets, macros, strutils

const newPrefix = "new"
const enumSuffix = "Kind"

proc isVar(node: NimNode): bool =
  node.kind == nnkIdent and node.strVal[0].isLowerAscii

proc wrap(node: NimNode, dataType: NimNode, field: Field): NimNode =
  let enumName = ident(dataType.strVal & enumSuffix)
  if node.isVar:
    let s = node.strVal
    quote do: Var(name: `s`)
  else:
    case field:
      of Identifier:
        let enumChoice = newDotExpr(enumName, ident(dataType.strVal & "Type0"))
        quote do: `dataType`(kind: `enumChoice`, type0: `node`)
      of Attribute:
        let enumChoice = newDotExpr(enumName, ident(dataType.strVal & "Type1"))
        quote do: `dataType`(kind: `enumChoice`, type1: `node`)
      of Value:
        let newProc = ident(newPrefix & dataType.strVal)
        quote do: `newProc`(`node`)

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
  let id = node[0].wrap(dataType, Identifier)
  let attr = node[1].wrap(dataType, Attribute)
  let value = node[2].wrap(dataType, Value)
  if filter != nil:
    let fn = genSym(nskLet, "fn")
    let v = genSym(nskParam, "v")
    let usedIds = getUsedIds(ids, filter)
    let letNode = createLet(usedIds, v)
    quote do:
      let `fn` = proc (`v`: Table[string, `dataType`]): bool =
        `letNode`
        `filter`
      add(`prod`, `id`, `attr`, `value`, `fn`)
  else:
    quote do:
      add(`prod`, `id`, `attr`, `value`)

proc parseWhat(name: string, dataType: NimNode, node: NimNode, condNode: NimNode, thenNode: NimNode): NimNode =
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
      var `prod` = newProduction[`dataType`](`name`, proc (`v`: Table[string, `dataType`]) =
        `letNode`
        `thenNode`
      )
    )
  else:
    result = newStmtList(quote do:
      var `prod` = newProduction[`dataType`](`name`, proc (`v`: Table[string, `dataType`]) = discard
      )
    )

  for condNum in 0 ..< node.len:
    let child = node[condNum]
    result.add addCond(datatype, ids, prod, child, if conds.hasKey(condNum): conds[condNum] else: nil)
  result.add prod

macro rule*(sig: untyped, body: untyped): untyped =
  expectKind(body, nnkStmtList)
  result = newStmtList()
  var t: Table["string", NimNode]
  for child in body:
    expectKind(child, nnkCall)
    let id = child[0]
    expectKind(id, nnkIdent)
    t[id.strVal] = child[1]

  let name = if sig.kind == nnkCall: sig[0].strVal else: ""
  let dataType = if sig.kind == nnkCall: sig[1] else: sig
  result.add parseWhat(
    name,
    dataType,
    t["what"],
    if t.hasKey("cond"): t["cond"] else: nil,
    if t.hasKey("then"): t["then"] else: nil
  )

proc createBranch(dataType: NimNode, index: int, typ: NimNode): NimNode =
  result = newNimNode(nnkOfBranch)
  var list = newNimNode(nnkRecList)
  list.add(newIdentDefs(ident("type" & $index), typ))
  result.add(ident(dataType.strVal & "Type" & $index), list)

proc createEnum(name: NimNode, dataType: NimNode, types: seq[NimNode]): NimNode =
  result = newNimNode(nnkTypeDef).add(
    newNimNode(nnkPragmaExpr).add(name).add(
      newNimNode(nnkPragma).add(ident("pure"))),
    newEmptyNode())
  var choices = newNimNode(nnkEnumTy).add(newEmptyNode())
  for i in 0 ..< types.len:
    choices.add(ident(dataType.strVal & "Type" & $i))
  result.add(choices)

proc createTypes(dataType: NimNode, enumName: NimNode, types: seq[NimNode]): NimNode =
  let enumType = createEnum(postfix(enumName, "*"), dataType, types)
  var cases = newNimNode(nnkRecCase)
  cases.add(newIdentDefs(postfix(ident("kind"), "*"), enumName))
  for i in 0 ..< types.len:
    cases.add(createBranch(dataType, i, types[i]))

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

proc createEqBranch(dataType: NimNode, index: int): NimNode =
  let keyNode = ident("type" & $index)
  result = newNimNode(nnkOfBranch)
  let eq = infix(newDotExpr(ident("a"), keyNode), "==", newDotExpr(ident("b"), keyNode))
  let list = newStmtList(newNimNode(nnkReturnStmt).add(eq))
  result.add(ident(dataType.strVal & "Type" & $index), list)

proc createEqProc(dataType: NimNode, types: seq[NimNode]): NimNode =
  var cases = newNimNode(nnkCaseStmt).add(newDotExpr(ident("a"), ident("kind")))
  for i in 0 ..< types.len:
    cases.add(createEqBranch(dataType, i))

  let body = quote do:
    if a.kind == b.kind:
      `cases`
    else:
      return false

  newProc(
    name = postfix(ident("=="), "*"),
    params = [
      ident("bool"),
      newIdentDefs(ident("a"), dataType),
      newIdentDefs(ident("b"), dataType)
    ],
    body = newStmtList(body)
  )

proc createNewProc(dataType: NimNode, enumName: NimNode, index: int, typ: NimNode): NimNode =
  let enumChoice = newDotExpr(enumName, ident(dataType.strVal & "Type" & $index))
  let id = ident("type" & $index)
  let x = ident("x")
  let body = quote do:
    `dataType`(kind: `enumChoice`, `id`: `x`)

  newProc(
    name = postfix(ident(newPrefix & dataType.strVal), "*"),
    params = [
      dataType,
      newIdentDefs(x, typ)
    ],
    body = newStmtList(body)
  )

proc createNewProcs(dataType: NimNode, enumName: NimNode, types: seq[NimNode]): NimNode =
  result = newStmtList()
  for i in 0 ..< types.len:
    result.add(createNewProc(dataType, enumName, i, types[i]))

macro schema*(body: untyped): untyped =
  expectKind(body, nnkCall)
  var types: seq[NimNode]
  for i in 1 ..< body.len:
    let typ = body[i]
    expectKind(typ, nnkIdent)
    assert not (typ in types)
    types.add(typ)

  let dataType = body[0]
  expectKind(dataType, nnkIdent)
  let enumName = ident(dataType.strVal & enumSuffix)
  newStmtList(
    createTypes(dataType, enumName, types),
    createEqProc(dataType, types),
    createNewProcs(dataType, enumName, types)
  )

proc wrapWithNewProc(procName: NimNode, session: NimNode, id: NimNode, attr: NimNode, value: NimNode): NimNode =
  let typeNode = session.getTypeImpl[2][0][1]
  expectKind(typeNode, nnkSym)
  let newProc = ident(newPrefix & typeNode.strVal)
  quote do:
    `procName`(`session`, (`newProc`(`id`), `newProc`(`attr`), `newProc`(`value`)))

macro insert*(session: Session, id: untyped, attr: untyped, value: untyped): untyped =
  wrapWithNewProc(ident("insertFact"), session, id, attr, value)

macro remove*(session: Session, id: untyped, attr: untyped, value: untyped): untyped =
  wrapWithNewProc(ident("removeFact"), session, id, attr, value)
