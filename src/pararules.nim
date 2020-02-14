import pararules/engine, tables, sets, macros, strutils

const
  initPrefix = "init"
  checkPrefix = "check"
  attrToTypePrefix = "attrToType"
  typeToNamePrefix = "typeToName"
  typePrefix = "type"
  typeEnumPrefix = "Type"
  enumSuffix = "Kind"
  intTypeNum = 0
  attrTypeNum = 1
  idTypeNum = 2

type
  VarInfo = tuple[condNum: int, typeNum: int]

proc isVar(node: NimNode): bool =
  node.kind == nnkIdent and node.strVal[0].isLowerAscii

proc wrap(parentNode: NimNode, dataType: NimNode, field: Field): NimNode =
  let enumName = ident(dataType.strVal & enumSuffix)
  let node = parentNode[field.ord]
  if node.isVar:
    let s = node.strVal
    quote do: Var(name: `s`)
  else:
    case field:
      of Identifier:
        let enumChoice = newDotExpr(enumName, ident(dataType.strVal & typeEnumPrefix & $intTypeNum))
        quote do: `dataType`(kind: `enumChoice`, type0: `node`.ord)
      of Attribute:
        let enumChoice = newDotExpr(enumName, ident(dataType.strVal & typeEnumPrefix & $attrTypeNum))
        quote do: `dataType`(kind: `enumChoice`, type1: `node`)
      of Value:
        let
          dataNode = genSym(nskLet, "node")
          checkProc = ident(checkPrefix & dataType.strVal)
          newProc = ident(initPrefix & dataType.strVal)
          attrName = ident(parentNode[1].strVal)
        quote do:
          let `dataNode` = `newProc`(`node`)
          when not defined(release):
            `checkProc`(`attrName`, `dataNode`.kind.ord)
          `dataNode`

proc createVars(vars: OrderedTable[string, VarInfo], paramNode: NimNode): NimNode =
  result = newStmtList()
  for (varName, varInfo) in vars.pairs:
    let typeField = ident(typePrefix & $varInfo.typeNum)
    result.add(newVarStmt(
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
  let id = node.wrap(dataType, Identifier)
  let attr = node.wrap(dataType, Attribute)
  let value = node.wrap(dataType, Value)
  let extraArg =
    if node.len == 4:
      expectKind(node[3], nnkExprEqExpr)
      node[3]
    elif node.len > 4:
      raise newException(Exception, "Too many arguments inside 'what' condition")
    else:
      newNimNode(nnkExprEqExpr).add(ident("then")).add(true.newLit)
  if filter != nil:
    let fn = genSym(nskLet, "fn")
    let v = genSym(nskParam, "v")
    let usedVars = getUsedVars(vars, filter)
    let varNode = createVars(usedVars, v)
    quote do:
      let `fn` = proc (`v`: Table[string, `dataType`]): bool =
        `varNode`
        `filter`
      add(`prod`, `id`, `attr`, `value`, `fn`, `extraArg`)
  else:
    quote do:
      add(`prod`, `id`, `attr`, `value`, nil, `extraArg`)

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
          of 0: intTypeNum
          of 1: attrTypeNum
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
    session = ident("session")

  var queryBody = newNimNode(nnkTupleConstr)
  for (varName, varInfo) in vars.pairs:
    let typeField = ident(typePrefix & $varInfo.typeNum)
    queryBody.add(newNimNode(nnkExprColonExpr).add(ident(varName)).add(quote do: `v2`[`varName`].`typeField`))

  if thenNode != nil:
    let usedVars = getUsedVars(vars, thenNode)
    let varNode = createVars(usedVars, v)
    result = newStmtList(quote do:
      let `callback` = proc (`session`: var Session[`dataType`], `v`: Table[string, `dataType`]) =
        `session`.insideRule = true
        `varNode`
        `thenNode`
      let `query` = proc (`v2`: Table[string, `dataType`]): `tupleType` =
        `queryBody`
      var `prod` = initProduction[`dataType`, `tupleType`](`name`, `callback`, `query`)
    )
  else:
    result = newStmtList(quote do:
      let `callback` = proc (`session`: var Session[`dataType`], `v`: Table[string, `dataType`]) = discard
      let `query` = proc (`v2`: Table[string, `dataType`]): `tupleType` =
        `queryBody`
      var `prod` = initProduction[`dataType`, `tupleType`](`name`, `callback`, `query`)
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
  expectKind(sig, nnkCall)
  let dataType = sig[1]
  let attrToType = ident(attrToTypePrefix & dataType.strVal)
  let typeToName = ident(typeToNamePrefix & dataType.strVal)
  quote do:
    ruleWithAttrs(`sig`, `attrToType`, `typeToName`, `body`)

proc getRuleName(rule: NimNode): string =
  expectKind(rule, nnkCommand)
  let call = rule[1]
  expectKind(call, nnkCall)
  let id = call[0]
  expectKind(id, nnkIdent)
  id.strVal

macro ruleset*(rules: untyped): untyped =
  expectKind(rules, nnkStmtList)
  result = newNimNode(nnkTupleConstr)
  for r in rules:
    let name = r.getRuleName
    result.add(newNimNode(nnkExprColonExpr).add(ident(name)).add(r))

proc getDataType(prod: NimNode): NimNode =
  let impl = prod.getTypeImpl
  expectKind(impl, nnkObjectTy)
  let recList = impl[2]
  expectKind(recList, nnkRecList)
  let alphaNode = recList[0]
  expectKind(alphaNode, nnkIdentDefs)
  let bracketExpr = alphaNode[1]
  expectKind(bracketExpr, nnkBracketExpr)
  let typ = bracketExpr[1]
  expectKind(typ, nnkSym)
  typ

proc createParamsArray(dataType: NimNode, args: NimNode): NimNode =
  result = newNimNode(nnkTableConstr)
  let newProc = ident(initPrefix & dataType.strVal)
  for arg in args:
    expectKind(arg, nnkExprEqExpr)
    let name = arg[0].strVal.newLit
    let val = arg[1]
    result.add(newNimNode(nnkExprColonExpr).add(name).add(quote do: `newProc`(`val`)))

macro find*(session: Session, prod: Production, args: varargs[untyped]): untyped =
  let dataType = prod.getDataType
  if args.len > 0:
    let params = createParamsArray(dataType, args)
    quote do:
      findIndex(`session`, `prod`, `params`)
  else:
    quote do:
      findIndex(`session`, `prod`)

macro findAll*(session: Session, prod: Production, args: varargs[untyped]): untyped =
  let dataType = prod.getDataType
  if args.len > 0:
    let params = createParamsArray(dataType, args)
    quote do:
      findAllIndices(`session`, `prod`, `params`)
  else:
    quote do:
      findAllIndices(`session`, `prod`)

macro query*(session: Session, prod: Production, args: varargs[untyped]): untyped =
  let dataType = prod.getDataType
  if args.len > 0:
    let params = createParamsArray(dataType, args)
    quote do:
      get(`session`, `prod`, findIndex(`session`, `prod`, `params`))
  else:
    quote do:
      get(`session`, `prod`, findIndex(`session`, `prod`))

proc createBranch(dataType: NimNode, index: int, typ: NimNode): NimNode =
  result = newNimNode(nnkOfBranch)
  var list = newNimNode(nnkRecList)
  let field = postfix(ident(typePrefix & $index), "*")
  list.add(newIdentDefs(field, typ))
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

proc createInitProc(dataType: NimNode, enumName: NimNode, index: int, typ: NimNode): NimNode =
  let x = ident("x")
  let body =
    if index == idTypeNum:
      let enumChoice = newDotExpr(enumName, ident(dataType.strVal & typeEnumPrefix & $intTypeNum))
      let id = ident(typePrefix & $intTypeNum)
      quote do:
        `dataType`(kind: `enumChoice`, `id`: `x`.ord)
    else:
      let enumChoice = newDotExpr(enumName, ident(dataType.strVal & typeEnumPrefix & $index))
      let id = ident(typePrefix & $index)
      quote do:
        `dataType`(kind: `enumChoice`, `id`: `x`)

  newProc(
    name = postfix(ident(initPrefix & dataType.strVal), "*"),
    params = [
      dataType,
      newIdentDefs(x, typ)
    ],
    body = newStmtList(body)
  )

proc createInitProcs(dataType: NimNode, enumName: NimNode, types: seq[NimNode]): NimNode =
  result = newStmtList()
  for i in 0 ..< types.len:
    result.add(createInitProc(dataType, enumName, i, types[i]))

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
    let branchBody =
      if typeNum == intTypeNum:
        let correctTypeNameAlt = types[idTypeNum].strVal
        quote do:
          if `value` != `correctTypeNum` and `value` != idTypeNum:
            raise newException(Exception, $`attr` & " should be a " & `correctTypeName` & " or a " & `correctTypeNameAlt`)
      else:
        quote do:
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

proc createUpdateProc(dataType: NimNode, intType: NimNode, attrType: NimNode, idType: NimNode, valueType: NimNode, valueTypeNum: int, procName: string): NimNode =
  let
    procId = ident(procName)
    engineProcId = block:
      if procName == "insert":
        bindSym("insertFact")
      else:
        bindSym("removeFact")
    checkProcId = ident(checkPrefix & dataType.strVal)
    newProc = ident(initPrefix & dataType.strVal)
    session = ident("session")
    sessionType = newNimNode(nnkVarTy).add(newNimNode(nnkBracketExpr).add(bindSym("Session")).add(dataType))
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
      newIdentDefs(id, infix(idType, "or", intType)),
      newIdentDefs(attr, attrType),
      newIdentDefs(value, valueType)
    ],
    body = newStmtList(body)
  )

proc createUpdateProcs(dataType: NimNode, types: seq[NimNode], procName: string): NimNode =
  result = newStmtList()
  for i in 0 ..< types.len:
    result.add(createUpdateProc(dataType, types[0], types[1], types[2], types[i], i, procName))

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
  if sig.len != 3:
    raise newException(Exception, "The schema requires two arguments: the id and attribute enums")

  let
    idType = sig[1]
    attrType = sig[2]
    intType = ident("int")
  expectKind(idType, nnkIdent)
  expectKind(attrType, nnkIdent)

  var types: seq[NimNode]
  types.add(intType)
  types.add(attrType)
  types.add(idType)

  expectKind(body, nnkStmtList)
  var attrs: Table[string, int]
  for pair in body:
    expectKind(pair, nnkCall)
    let attr = pair[0].strVal
    if not attr[0].isUpperAscii:
      raise newException(Exception, attr & " is an invalid attribute name because it must start with an uppercase letter")
    var typ = pair[1][0]
    if typ.kind == nnkBracketExpr:
      let message = """
All types in the schema must be simple names.
If you have a type that takes type parameters, such as `seq[string]`,
make a type alias such as `type Strings = seq[string]` and then
use `Strings` in the schema.
      """
      raise newException(Exception, message)
    expectKind(typ, nnkIdent)
    assert not (attr in attrs)
    if typ == idType:
      typ = intType
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
    createInitProcs(dataType, enumName, types),
    createCheckProc(dataType, types, attrs),
    createUpdateProcs(dataType, types, "insert"),
    createUpdateProcs(dataType, types, "remove"),
    createConstants(dataType, types, attrs)
  )

# these wrapper macros are only here so
# the engine doesn't need to be imported directly

macro initSession*(dataType: type): untyped =
  quote do:
    initSession[`dataType`]()

macro add*(session: Session, production: Production): untyped =
  quote do:
    add(`session`, `production`)

macro get*(session: Session, production: Production, index: int): untyped =
  quote do:
    get(`session`, `production`, `index`)

