import pararules/engine, tables, sets, macros, strutils

const newPrefix = "new"
const checkPrefix = "check"
const attrToTypePrefix = "attrToType"
const typeToNamePrefix = "typeToName"
const typePrefix = "type"
const typeEnumPrefix = "Type"
const enumSuffix = "Kind"

type
  VarInfo = tuple[condNum: int, typeNum: int]

proc isVar(node: NimNode): bool =
  node.kind == nnkIdent and node.strVal[0].isLowerAscii

proc wrap(parentNode: NimNode, dataType: NimNode, index: int): NimNode =
  let enumName = ident(dataType.strVal & enumSuffix)
  let node = parentNode[index]
  if node.isVar:
    let s = node.strVal
    quote do: Var(name: `s`)
  else:
    case index:
      of 0:
        let enumChoice = newDotExpr(enumName, ident(dataType.strVal & typeEnumPrefix & "0"))
        quote do: `dataType`(kind: `enumChoice`, type0: `node`)
      of 1:
        let enumChoice = newDotExpr(enumName, ident(dataType.strVal & typeEnumPrefix & "1"))
        quote do: `dataType`(kind: `enumChoice`, type1: `node`)
      else:
        let
          dataNode = genSym(nskLet, "node")
          checkProc = ident(checkPrefix & dataType.strVal)
          newProc = ident(newPrefix & dataType.strVal)
          attrName = ident(parentNode[1].strVal)
        quote do:
          let `dataNode` = `newProc`(`node`)
          when not defined(release):
            `checkProc`(`attrName`, `dataNode`.kind.ord)
          `dataNode`

proc createLet(vars: OrderedTable[string, VarInfo], paramNode: NimNode): NimNode =
  result = newStmtList()
  for (varName, varInfo) in vars.pairs:
    let typeField = ident(typePrefix & $varInfo.typeNum)
    result.add(newLetStmt(
      newIdentNode(varName),
      quote do:
        `paramNode`[`varName`].`typeField`
    ))

proc getVarsInNode(node: NimNode): HashSet[string] =
  if node.isVar:
    result.incl(node.strVal)
  for child in node:
    result = result.union(child.getVarsInNode)

proc parseCond(vars: OrderedTable[string, VarInfo], node: NimNode): Table[int, NimNode] =
  expectKind(node, nnkStmtList)
  for condNode in node:
    var condNum = 0
    for ident in condNode.getVarsInNode:
      if vars.hasKey(ident):
        condNum = max(condNum, vars[ident].condNum)
    if result.hasKey(condNum):
      let prevCond = result[condNum]
      result[condNum] = quote do:
        `prevCond` and `condNode`
    else:
      result[condNum] = condNode

proc getUsedVars(vars: OrderedTable[string, VarInfo], node: NimNode): OrderedTable[string, VarInfo] =
  for v in node.getVarsInNode:
    if vars.hasKey(v):
      result[v] = vars[v]

proc addCond(dataType: NimNode, vars: OrderedTable[string, VarInfo], prod: NimNode, node: NimNode, filter: NimNode): NimNode =
  expectKind(node, nnkPar)
  let id = node.wrap(dataType, 0)
  let attr = node.wrap(dataType, 1)
  let value = node.wrap(dataType, 2)
  if filter != nil:
    let fn = genSym(nskLet, "fn")
    let v = genSym(nskParam, "v")
    let usedVars = getUsedVars(vars, filter)
    let letNode = createLet(usedVars, v)
    quote do:
      let `fn` = proc (`v`: Table[string, `dataType`]): bool =
        `letNode`
        `filter`
      add(`prod`, `id`, `attr`, `value`, `fn`)
  else:
    quote do:
      add(`prod`, `id`, `attr`, `value`)

proc parseWhat(name: string, dataType: NimNode, attrs: Table[string, int], types: seq[string], node: NimNode, condNode: NimNode, thenNode: NimNode): NimNode =
  var vars: OrderedTable[string, VarInfo]
  for condNum in 0 ..< node.len:
    let child = node[condNum]
    expectKind(child, nnkPar)
    for i in 0..2:
      if child[i].isVar:
        if i == 1:
          raise newException(Exception, "Variables may not be placed in the attribute column")
        let s = child[i].strVal
        let typeNum = case i:
          of 0: 0
          of 1: 1
          else: attrs[child[1].strVal]
        if not vars.hasKey(s):
          vars[s] = (condNum, typeNum)

  expectKind(node, nnkStmtList)
  var conds: Table[int, NimNode]
  if condNode != nil:
    conds = parseCond(vars, condNode)

  let tupleType = newNimNode(nnkTupleTy)
  for (varName, varInfo) in vars.pairs:
    tupleType.add(newIdentDefs(ident(varName), ident(types[varInfo.typeNum])))

  let
    prod = genSym(nskVar, "prod")
    v = genSym(nskParam, "v")
    callback = genSym(nskLet, "callback")
    v2 = genSym(nskParam, "v")
    query = genSym(nskLet, "query")

  var queryBody = newNimNode(nnkTupleConstr)
  for (varName, varInfo) in vars.pairs:
    let typeField = ident(typePrefix & $varInfo.typeNum)
    queryBody.add(newNimNode(nnkExprColonExpr).add(ident(varName)).add(quote do: `v2`[`varName`].`typeField`))

  if thenNode != nil:
    let usedVars = getUsedVars(vars, thenNode)
    let letNode = createLet(usedVars, v)
    result = newStmtList(quote do:
      let `callback` = proc (`v`: Table[string, `dataType`]) =
        `letNode`
        `thenNode`
      let `query` = proc (`v2`: Table[string, `dataType`]): `tupleType` =
        `queryBody`
      var `prod` = newProduction[`dataType`, `tupleType`](`name`, `callback`, `query`)
    )
  else:
    result = newStmtList(quote do:
      let `callback` = proc (`v`: Table[string, `dataType`]) = discard
      let `query` = proc (`v2`: Table[string, `dataType`]): `tupleType` =
        `queryBody`
      var `prod` = newProduction[`dataType`, `tupleType`](`name`, `callback`, `query`)
    )

  for condNum in 0 ..< node.len:
    let child = node[condNum]
    result.add addCond(datatype, vars, prod, child, if conds.hasKey(condNum): conds[condNum] else: nil)
  result.add prod

macro ruleWithAttrs*(sig: untyped, attrsNode: typed, typesNode: typed, body: untyped): untyped =
  expectKind(body, nnkStmtList)
  result = newStmtList()
  var t: Table[string, NimNode]
  for child in body:
    expectKind(child, nnkCall)
    let id = child[0]
    expectKind(id, nnkIdent)
    t[id.strVal] = child[1]

  let attrsImpl = attrsNode.getImpl
  expectKind(attrsImpl, nnkBracket)
  var attrs: Table[string, int]
  for child in attrsImpl:
    expectKind(child, nnkTupleConstr)
    let key = child[0].strVal
    let val = child[1].intVal
    attrs[key] = cast[int](val)

  let typesImpl = typesNode.getImpl
  expectKind(typesImpl, nnkBracket)
  var types: seq[string]
  for child in typesImpl:
    types.add(child.strVal)

  expectKind(sig, nnkCall)
  let name = sig[0].strVal
  let dataType = sig[1]
  result.add parseWhat(
    name,
    dataType,
    attrs,
    types,
    t["what"],
    if t.hasKey("cond"): t["cond"] else: nil,
    if t.hasKey("then"): t["then"] else: nil
  )

macro rule*(sig: untyped, body: untyped): untyped =
  let dataType = if sig.kind == nnkCall: sig[1] else: sig
  let attrToType = ident(attrToTypePrefix & dataType.strVal)
  let typeToName = ident(typeToNamePrefix & dataType.strVal)
  quote do:
    ruleWithAttrs(`sig`, `attrToType`, `typeToName`, `body`)

proc createBranch(dataType: NimNode, index: int, typ: NimNode): NimNode =
  result = newNimNode(nnkOfBranch)
  var list = newNimNode(nnkRecList)
  list.add(newIdentDefs(ident(typePrefix & $index), typ))
  result.add(ident(dataType.strVal & typeEnumPrefix & $index), list)

proc createEnum(name: NimNode, dataType: NimNode, types: seq[NimNode]): NimNode =
  result = newNimNode(nnkTypeDef).add(
    newNimNode(nnkPragmaExpr).add(name).add(
      newNimNode(nnkPragma).add(ident("pure"))),
    newEmptyNode())
  var choices = newNimNode(nnkEnumTy).add(newEmptyNode())
  for i in 0 ..< types.len:
    choices.add(ident(dataType.strVal & typeEnumPrefix & $i))
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
  let keyNode = ident(typePrefix & $index)
  result = newNimNode(nnkOfBranch)
  let eq = infix(newDotExpr(ident("a"), keyNode), "==", newDotExpr(ident("b"), keyNode))
  let list = newStmtList(newNimNode(nnkReturnStmt).add(eq))
  result.add(ident(dataType.strVal & typeEnumPrefix & $index), list)

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
  let enumChoice = newDotExpr(enumName, ident(dataType.strVal & typeEnumPrefix & $index))
  let id = ident(typePrefix & $index)
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

proc createCheckProc(dataType: NimNode, types: seq[NimNode], attrs: Table[string, int]): NimNode =
  let
    procId = ident(checkPrefix & dataType.strVal)
    attr = ident("attr")
    value = ident("valueTypeNum")
    body = newNimNode(nnkCaseStmt).add(attr)
    attrType = types[1]

  for (typeName, typeNum) in attrs.pairs:
    var branch = newNimNode(nnkOfBranch)
    let correctTypeNum = typeNum.newLit
    let correctTypeName = types[typeNum].strVal
    let branchBody = quote do:
      if `value` != `correctTypeNum`:
        raise newException(Exception, $`attr` & " should be a " & `correctTypeName`)
    branch.add(ident(typeName), branchBody)
    body.add(branch)

  newProc(
    name = postfix(procId, "*"),
    params = [
      ident("void"),
      newIdentDefs(attr, attrType),
      newIdentDefs(value, ident("int"))
    ],
    body = newStmtList(body)
  )

proc createUpdateProc(dataType: NimNode, idType: NimNode, attrType: NimNode, valueType: NimNode, valueTypeNum: int, procName: string): NimNode =
  let
    procId = ident(procName)
    engineProcId = ident(procName & "Fact")
    checkProcId = ident(checkPrefix & dataType.strVal)
    newProc = ident(newPrefix & dataType.strVal)
    session = ident("session")
    sessionType = newNimNode(nnkVarTy).add(block:
      var node = newNimNode(nnkBracketExpr)
      node.add(ident("Session"))
      node.add(dataType)
      node
    )
    id = ident("id")
    attr = ident("attr")
    value = ident("value")
    valueTypeLit = valueTypeNum.newLit
    body = quote do:
      when not defined(release):
        `checkProcId`(`attr`, `valueTypeLit`)
      `engineProcId`(`session`, (`newProc`(`id`), `newProc`(`attr`), `newProc`(`value`)))

  newProc(
    name = postfix(procId, "*"),
    params = [
      ident("void"),
      newIdentDefs(session, sessionType),
      newIdentDefs(id, idType),
      newIdentDefs(attr, attrType),
      newIdentDefs(value, valueType)
    ],
    body = newStmtList(body)
  )

proc createUpdateProcs(dataType: NimNode, types: seq[NimNode], procName: string): NimNode =
  result = newStmtList()
  for i in 0 ..< types.len:
    result.add(createUpdateProc(dataType, types[0], types[1], types[i], i, procName))

proc createConstants(dataType: NimNode, types: seq[NimNode], attrs: Table[string, int]): NimNode =
  let attrToTypeId = ident(attrToTypePrefix & dataType.strVal)
  var attrToTypeTable = newNimNode(nnkTableConstr)
  let typeToNameId = ident(typeToNamePrefix & dataType.strVal)
  var typeToNameArray = newNimNode(nnkBracket)
  for (attr, typeNum) in attrs.pairs():
    attrToTypeTable.add(newNimNode(nnkExprColonExpr).add(attr.newLit).add(typeNum.newLit))
  for typ in types:
    typeToNameArray.add(typ.strVal.newLit)
  quote do:
    const `attrToTypeId`* = `attrToTypeTable`
    const `typeToNameId`* = `typeToNameArray`

macro schema*(sig: untyped, body: untyped): untyped =
  expectKind(sig, nnkCall)
  var types: seq[NimNode]
  for i in 1 ..< sig.len:
    let typ = sig[i]
    expectKind(typ, nnkIdent)
    types.add(typ)

  expectKind(body, nnkStmtList)
  var attrs: Table[string, int]
  for pair in body:
    expectKind(pair, nnkCall)
    let attr = pair[0].strVal
    let typ = pair[1][0]
    assert not (attr in attrs)
    if not (typ in types):
      types.add(typ)
    let index = types.find(typ)
    attrs[attr] = index

  let dataType = sig[0]
  expectKind(dataType, nnkIdent)

  let enumName = ident(dataType.strVal & enumSuffix)
  newStmtList(
    createTypes(dataType, enumName, types),
    createEqProc(dataType, types),
    createNewProcs(dataType, enumName, types),
    createCheckProc(dataType, types, attrs),
    createUpdateProcs(dataType, types, "insert"),
    createUpdateProcs(dataType, types, "remove"),
    createConstants(dataType, types, attrs)
  )

