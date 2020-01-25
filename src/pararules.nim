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
  for s in ids.keys():
    result.add(newLetStmt(
      newIdentNode(s),
      quote do:
        `paramNode`[`s`]
    ))

proc getVarsInNode(node: NimNode): HashSet[string] =
  if node.isVar:
    result.incl(node.strVal)
  for child in node:
    result = result.union(child.getVarsInNode())

proc parseCond(ids: Table[string, int], node: NimNode): Table[int, NimNode] =
  expectKind(node, nnkStmtList)
  for condNode in node:
    var condNum = 0
    for ident in condNode.getVarsInNode():
      if ids.hasKey(ident):
        condNum = max(condNum, ids[ident])
    if result.hasKey(condNum):
      let prevcond = result[condNum]
      result[condNum] = quote do:
        `prevCond` and `condNode`
    else:
      result[condNum] = condNode

proc addCond(dataType:NimNode, ids: Table[string, int], prod: NimNode, node: NimNode, filter: NimNode): NimNode =
  expectKind(node, nnkPar)
  let id = wrapVar(node[0])
  let attr = wrapVar(node[1])
  let value = wrapVar(node[2])
  if filter != nil:
    let fn = genSym(nskLet, "fn")
    let v = genSym(nskParam, "v")
    let letNode = createLet(ids, v)
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
    let letNode = createLet(ids, v)
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

  # we must clear the ids and add them again
  # so addCond only gets the ids available to
  # that condition
  ids.clear()

  for condNum in 0 ..< node.len:
    let child = node[condNum]
    expectKind(child, nnkPar)
    for i in 0..2:
      if child[i].kind == nnkIdent:
        let s = child[i].strVal
        if not ids.hasKey(s):
          ids[s] = condNum
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
