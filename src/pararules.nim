import pararules/[cows, engine], tables, sets, macros, strutils

const
  initPrefix = "init"
  checkPrefix = "check"
  attrToTypePrefix = "attrToType"
  typeToNamePrefix = "typeToName"
  typePrefix = "slot"
  enumSuffix = "Kind"
  intTypeNum = 0
  attrTypeNum = 1
  idTypeNum = 2

## rule, ruleset

proc typeToSimpleName(node: NimNode): string =
  case node.kind:
  of nnkIdent:
    node.strVal
  of nnkDotExpr:
    node[0].strVal & "." & node[1].strVal
  else:
    raise newException(Exception, "Can't get simple name for type: " & $node)

proc simpleNameToType(name: string): NimNode =
  let parts = strutils.split(name, ".")
  case parts.len:
  of 1:
    ident(name)
  of 2:
    newDotExpr(ident(parts[0]), ident(parts[1]))
  else:
    raise newException(Exception, "Invalid ident: " & name)

type
  VarInfo = tuple[condNum: int, typeNum: int]

proc isVar(node: NimNode): bool =
  node.kind == nnkIdent and node.strVal[0].isLowerAscii

proc wrap(parentNode: NimNode, dataType: NimNode, field: Field): NimNode =
  let node = parentNode[field.ord]
  if node.isVar:
    let s = node.strVal
    quote do: Var(name: `s`)
  else:
    let enumName = ident(dataType.strVal & enumSuffix)
    case field:
      of Identifier:
        let enumChoice = newDotExpr(enumName, ident(dataType.strVal & enumSuffix & $intTypeNum))
        quote do: `dataType`(kind: `enumChoice`, slot0: `node`.ord)
      of Attribute:
        let enumChoice = newDotExpr(enumName, ident(dataType.strVal & enumSuffix & $attrTypeNum))
        quote do: `dataType`(kind: `enumChoice`, slot1: `node`)
      of Value:
        let
          dataNode = genSym(nskLet, "node")
          checkProc = ident(checkPrefix & dataType.strVal)
          initProc = ident(initPrefix & dataType.strVal)
          attrName = ident(parentNode[Attribute.ord].strVal)
        quote do:
          let `dataNode` = `initProc`(`node`)
          when not defined(release):
            `checkProc`(`attrName`, `dataNode`.kind.ord)
          `dataNode`

proc destructureMatch(vars: OrderedTable[string, VarInfo], paramNode: NimNode): NimNode =
  result = newStmtList()
  for (varName, varInfo) in vars.pairs:
    let typeField = ident(typePrefix & $varInfo.typeNum)
    result.add(newLetStmt(
      newIdentNode(varName),
      quote do:
        `paramNode`[`varName`].`typeField`
    ))

proc destructureMatch(vars: seq[string], paramNode: NimNode): NimNode =
  result = newStmtList()
  for varName in vars:
    let varIdent = ident(varName)
    result.add(newLetStmt(
      varIdent,
      quote do:
        `paramNode`.`varIdent`
    ))

proc getVarsInNode(node: NimNode): HashSet[string] =
  if node.isVar:
    result.incl(node.strVal)
  for child in node:
    result = result.union(child.getVarsInNode)

proc parseCond(node: NimNode): NimNode =
  expectKind(node, nnkStmtList)
  for condNode in node:
    if result == nil:
      result = condNode
    else:
      let prevCond = result
      result = quote do:
        `prevCond` and `condNode`

proc getUsedVars(vars: OrderedTable[string, VarInfo], node: NimNode): OrderedTable[string, VarInfo] =
  for v in node.getVarsInNode:
    if vars.hasKey(v):
      result[v] = vars[v]

proc addCond(dataType: NimNode, vars: OrderedTable[string, VarInfo], prod: NimNode, node: NimNode): NimNode =
  expectKind(node, {nnkPar, nnkTupleConstr})
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
  quote do:
    engine.add(`prod`, `id`, `attr`, `value`, `extraArg`)

proc parseWhat(name: string, dataType: NimNode, matchType: NimNode, attrs: Table[string, int], types: seq[string], node: NimNode, condNode: NimNode, thenNode: NimNode, thenFinallyNode: NimNode): NimNode =
  var vars: OrderedTable[string, VarInfo]
  for condNum in 0 ..< node.len:
    let child = node[condNum]
    expectKind(child, {nnkPar, nnkTupleConstr})
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
  var condBody: NimNode
  if condNode != nil:
    condBody = parseCond(condNode)

  let tupleType = newNimNode(nnkTupleTy)
  for (varName, varInfo) in vars.pairs:
    tupleType.add(newIdentDefs(ident(varName), types[varInfo.typeNum].simpleNameToType))

  let
    prod = genSym(nskVar, "prod")
    matchFn = genSym(nskLet, "matchFn")
    condFn = genSym(nskLet, "condFn")
    session = ident("session")
    match = ident("match")
    this = ident("this")

  let matchFnLet =
    block:
      let v = genSym(nskParam, "v")
      var queryBody = newNimNode(nnkTupleConstr)
      for (varName, varInfo) in vars.pairs:
        let typeField = ident(typePrefix & $varInfo.typeNum)
        queryBody.add(newNimNode(nnkExprColonExpr).add(ident(varName)).add(quote do: `v`[`varName`].`typeField`))
      quote do:
        let `matchFn` = proc (`v`: `matchType`): `tupleType` =
          `queryBody`

  let condFnLet =
    block:
      let v = genSym(nskParam, "v")
      if condBody != nil:
        let usedVars = getUsedVars(vars, condNode)
        let varNode = destructureMatch(usedVars, v)
        quote do:
          let `condFn` = proc (`v`: `matchType`): bool =
            `varNode`
            `condBody`
      else:
        quote do:
          let `condFn`: proc (`v`: `matchType`): bool = nil

  result = newStmtList()

  var thenFn: NimNode
  if thenNode != nil:
    let usedVars = getUsedVars(vars, thenNode)
    var varNames: seq[string]
    for (varName, _) in usedVars.pairs:
      varNames.add(varName)
    let varNode = destructureMatch(varNames, match)
    let thenFnSym = genSym(nskLet, "thenFn")
    result.add quote do:
      let `thenFnSym` = proc (`session`: var Session[`dataType`, `matchType`], `this`: Production[`dataType`, `tupleType`, `matchType`], `match`: `tupleType`) =
        `varNode`
        `thenNode`
    thenFn = thenFnSym
  else:
    thenFn = quote do: nil

  var thenFinallyFn: NimNode
  if thenFinallyNode != nil:
    let thenFinallyFnSym = genSym(nskLet, "thenFinallyFn")
    result.add quote do:
      let `thenFinallyFnSym` = proc (`session`: var Session[`dataType`, `matchType`], `this`: Production[`dataType`, `tupleType`, `matchType`]) =
        `thenFinallyNode`
    thenFinallyFn = thenFinallyFnSym
  else:
    thenFinallyFn = quote do: nil

  result.add matchFnLet
  result.add condFnLet
  result.add quote do:
    var `prod` = initProduction[`dataType`, `tupleType`, `matchType`](`name`, `matchFn`, `condFn`, `thenFn`, `thenFinallyFn`)

  for condNum in 0 ..< node.len:
    let child = node[condNum]
    result.add addCond(datatype, vars, prod, child)
  result.add prod

const blockTypes = ["what", "cond", "then", "thenFinally"].toHashSet

macro ruleWithAttrs*(sig: untyped, dataType: untyped, matchType: untyped, attrsNode: typed, typesNode: typed, body: untyped): untyped =
  expectKind(body, nnkStmtList)
  result = newStmtList()
  var t: Table[string, NimNode]
  for child in body:
    expectKind(child, nnkCall)
    let id = child[0]
    expectKind(id, nnkIdent)
    let blockName = id.strVal
    if not blockTypes.contains(blockName):
      raise newException(Exception, "Unrecognized block name: " & blockName)
    t[blockName] = child[1]

  let attrsImpl =
    # getImpl works differently for const nodes in nim 2.0
    when (NimMajor, NimMinor) >= (1, 9):
      attrsNode.getImpl[2]
    else:
      attrsNode.getImpl
  expectKind(attrsImpl, nnkBracket)
  var attrs: Table[string, int]
  for child in attrsImpl:
    expectKind(child, nnkTupleConstr)
    let key = child[0].strVal
    let val = child[1].intVal
    attrs[key] = cast[int](val)

  let typesImpl =
    # getImpl works differently for const nodes in nim 2.0
    when (NimMajor, NimMinor) >= (1, 9):
      typesNode.getImpl[2]
    else:
      typesNode.getImpl
  expectKind(typesImpl, nnkBracket)
  var types: seq[string]
  for child in typesImpl:
    types.add(child.strVal)

  expectKind(sig, nnkCall)
  let name = sig[0].strVal
  result.add parseWhat(
    name,
    dataType,
    matchType,
    attrs,
    types,
    t["what"],
    if t.hasKey("cond"): t["cond"] else: nil,
    if t.hasKey("then"): t["then"] else: nil,
    if t.hasKey("thenFinally"): t["thenFinally"] else: nil,
  )

macro rule*(sig: untyped, body: untyped): untyped =
  expectKind(sig, nnkCall)
  let dataType = sig[1]
  let matchType =
    if sig.len > 2:
      sig[2]
    else:
      quote do:
        Vars[`dataType`]
  let attrToType = ident(attrToTypePrefix & dataType.strVal)
  let typeToName = ident(typeToNamePrefix & dataType.strVal)
  quote do:
    ruleWithAttrs(`sig`, `dataType`, `matchType`, `attrToType`, `typeToName`, `body`)

proc flattenRules(rules: NimNode): seq[NimNode] =
  for r in rules:
    if r.kind == nnkCommand:
      result.add(r)
    elif r.kind == nnkStmtList:
      result.add(flattenRules(r))
    else:
      expectKind(r, nnkCommand)

proc getRuleName(rule: NimNode): string =
  expectKind(rule, nnkCommand)
  let call = rule[1]
  expectKind(call, nnkCall)
  let id = call[0]
  expectKind(id, nnkIdent)
  id.strVal

proc makeTupleOfRules(rules: NimNode): NimNode =
  # flatten rules if there are multiple levels of statement lists
  let flatRules = newStmtList(flattenRules(rules))
  result = newNimNode(nnkTupleConstr)
  for r in flatRules:
    let name = r.getRuleName
    result.add(newNimNode(nnkExprColonExpr).add(ident(name)).add(r))

macro ruleset*(rules: untyped): untyped =
  makeTupleOfRules(rules)

## find, findAll, query

proc getDataType(session: NimNode): NimNode =
  let impl = session.getTypeImpl
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
  let initProc = ident(initPrefix & dataType.strVal)
  for arg in args:
    expectKind(arg, nnkExprEqExpr)
    let name = arg[0].strVal.newLit
    let val = arg[1]
    result.add(newNimNode(nnkExprColonExpr).add(name).add(quote do: `initProc`(`val`)))

macro find*(session: Session, prod: Production, args: varargs[untyped]): untyped =
  if args.len > 0:
    let dataType = session.getDataType
    let params = createParamsArray(dataType, args)
    quote do:
      engine.find(`session`, `prod`, `params`)
  else:
    quote do:
      engine.find(`session`, `prod`)

macro findAll*(session: Session, prod: Production, args: varargs[untyped]): untyped =
  if args.len > 0:
    let dataType = session.getDataType
    let params = createParamsArray(dataType, args)
    quote do:
      engine.findAll(`session`, `prod`, `params`)
  else:
    quote do:
      engine.findAll(`session`, `prod`)

macro query*(session: Session, prod: Production, args: varargs[untyped]): untyped =
  if args.len > 0:
    let dataType = session.getDataType
    let params = createParamsArray(dataType, args)
    quote do:
      engine.get(`session`, `prod`, engine.find(`session`, `prod`, `params`))
  else:
    quote do:
      engine.get(`session`, `prod`, engine.find(`session`, `prod`))

## schema

proc checkTypes(types: seq[NimNode]): NimNode =
  result = newStmtList()
  var index = 0
  for typ in types:
    for index2 in 0 ..< types.len:
      if index != index2:
        let
          typ2 = types[index2]
          msg = typ.typeToSimpleName & " is the same type as " & typ2.typeToSimpleName &
                  ", but they have different names. This is currently not allowed in the schema macro. " &
                  "Please use only one of these names."
        result.add(
          quote do:
            static:
              when `typ` is `typ2`:
                raise newException(Exception, `msg`)
        )
    index += 1

proc createVariantBranch(enumItemName: NimNode, fieldName: NimNode, typ: NimNode): NimNode =
  result = newNimNode(nnkOfBranch)
  var list = newNimNode(nnkRecList)
  let field = postfix(fieldName, "*")
  list.add(newIdentDefs(field, typ))
  result.add(enumItemName, list)

proc createVariantEnum(name: NimNode, enumItems: seq[NimNode]): NimNode =
  result = newNimNode(nnkTypeDef).add(
    newNimNode(nnkPragmaExpr).add(name).add(
      newNimNode(nnkPragma).add(ident("pure"))),
    newEmptyNode())
  var choices = newNimNode(nnkEnumTy).add(newEmptyNode())
  for item in enumItems:
    choices.add(item)
  result.add(choices)

proc createTypes(dataType: NimNode, enumName: NimNode, types: seq[NimNode]): NimNode =
  var enumItems: seq[NimNode]
  for i in 0 ..< types.len:
    enumItems.add(ident(dataType.strVal & enumSuffix & $i))
  let enumType = createVariantEnum(postfix(enumName, "*"), enumItems)
  var cases = newNimNode(nnkRecCase)
  cases.add(newIdentDefs(postfix(ident("kind"), "*"), enumName))
  for i in 0 ..< types.len:
    let
      enumItemName = ident(dataType.strVal & enumSuffix & $i)
      fieldName = ident(typePrefix & $i)
    cases.add(createVariantBranch(enumItemName, fieldName, types[i]))

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
  result.add(ident(dataType.strVal & enumSuffix & $index), list)

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
      let enumChoice = newDotExpr(enumName, ident(dataType.strVal & enumSuffix & $intTypeNum))
      let id = ident(typePrefix & $intTypeNum)
      quote do:
        `dataType`(kind: `enumChoice`, `id`: `x`.ord)
    else:
      let enumChoice = newDotExpr(enumName, ident(dataType.strVal & enumSuffix & $index))
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
    let correctTypeName = types[typeNum].typeToSimpleName
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
      elif procName == "retract":
        bindSym("retractFact")
      else:
        raise newException(Exception, "Invalid procName: " & procName)
    checkProcId = ident(checkPrefix & dataType.strVal)
    initProc = ident(initPrefix & dataType.strVal)
    session = ident("session")
    sessionType = newNimNode(nnkVarTy).add(newNimNode(nnkBracketExpr).add(bindSym("Session")).add(dataType).add(ident("auto")))
    id = ident("id")
    attr = ident("attr")
    value = ident("value")
    valueTypeLit = valueTypeNum.newLit
    body = quote do:
      when not defined(release):
        `checkProcId`(`attr`, `valueTypeLit`)
      `engineProcId`(`session`, (`initProc`(`id`), `initProc`(`attr`), `initProc`(`value`)))

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

proc createInsertProc(dataType: NimNode, intType: NimNode, attrType: NimNode, idType: NimNode): NimNode =
  let
    procId = ident("insert")
    engineProcId = bindSym("insertFact")
    checkProcId = ident(checkPrefix & dataType.strVal)
    initProc = ident(initPrefix & dataType.strVal)
    session = ident("session")
    sessionType = newNimNode(nnkVarTy).add(newNimNode(nnkBracketExpr).add(bindSym("Session")).add(dataType).add(ident("auto")))
    id = ident("id")
    attr = ident("attr")
    value = ident("value")
    body = quote do:
      when not defined(release):
        `checkProcId`(`attr`, `value`.kind.ord)
      `engineProcId`(`session`, (`initProc`(`id`), `initProc`(`attr`), `value`))

  newProc(
    name = postfix(procId, "*"),
    params = [
      ident("void"),
      newIdentDefs(session, sessionType),
      newIdentDefs(id, infix(idType, "or", intType)),
      newIdentDefs(attr, attrType),
      newIdentDefs(value, dataType)
    ],
    body = newStmtList(body)
  )

proc createRetractProc(dataType: NimNode, intType: NimNode, attrType: NimNode, idType: NimNode): NimNode =
  let
    procId = ident("retract")
    engineProcId = bindSym("retractFact")
    session = ident("session")
    sessionType = newNimNode(nnkVarTy).add(newNimNode(nnkBracketExpr).add(bindSym("Session")).add(dataType).add(ident("auto")))
    id = ident("id")
    attr = ident("attr")
    body = quote do:
      `engineProcId`(`session`, `id`.ord, `attr`.ord)

  newProc(
    name = postfix(procId, "*"),
    params = [
      ident("void"),
      newIdentDefs(session, sessionType),
      newIdentDefs(id, infix(idType, "or", intType)),
      newIdentDefs(attr, attrType),
    ],
    body = newStmtList(body)
  )

proc createContainsProc(dataType: NimNode, intType: NimNode, attrType: NimNode, idType: NimNode): NimNode =
  let
    procId = ident("contains")
    engineProcId = bindSym("contains")
    session = ident("session")
    sessionType = newNimNode(nnkVarTy).add(newNimNode(nnkBracketExpr).add(bindSym("Session")).add(dataType).add(ident("auto")))
    id = ident("id")
    attr = ident("attr")
    body = quote do:
      `engineProcId`(`session`, `id`.ord, `attr`.ord)

  newProc(
    name = postfix(procId, "*"),
    params = [
      ident("bool"),
      newIdentDefs(session, sessionType),
      newIdentDefs(id, infix(idType, "or", intType)),
      newIdentDefs(attr, attrType),
    ],
    body = newStmtList(body)
  )

proc createSessionProcs(dataType: NimNode, types: seq[NimNode]): NimNode =
  result = newStmtList()
  # create insert and retract procs for each value type
  for i in 0 ..< types.len:
    result.add(createUpdateProc(dataType, types[0], types[1], types[2], types[i], i, "insert"))
    result.add(createUpdateProc(dataType, types[0], types[1], types[2], types[i], i, "retract"))
  # create an insert proc whose value is wrapped in the object variant
  result.add(createInsertProc(dataType, types[0], types[1], types[2]))
  # create a retract proc that only requires the id and attr
  result.add(createRetractProc(dataType, types[0], types[1], types[2]))
  # create a contains proc that only requires the id and attr
  result.add(createContainsProc(dataType, types[0], types[1], types[2]))

proc createConstants(dataType: NimNode, types: seq[NimNode], attrs: Table[string, int]): NimNode =
  let attrToTypeId = ident(attrToTypePrefix & dataType.strVal)
  var attrToTypeTable = newNimNode(nnkTableConstr)
  let typeToNameId = ident(typeToNamePrefix & dataType.strVal)
  var typeToNameArray = newNimNode(nnkBracket)
  for (attr, typeNum) in attrs.pairs():
    attrToTypeTable.add(newNimNode(nnkExprColonExpr).add(attr.newLit).add(typeNum.newLit))
  for typ in types:
    typeToNameArray.add(typ.typeToSimpleName.newLit)
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
    if typ.kind notin {nnkIdent, nnkDotExpr}:
      let message = """
All types in the schema must be simple names.
If you have a type that takes type parameters, such as `seq[string]`,
make a type alias such as `type Strings = seq[string]` and then
use `Strings` in the schema.
      """
      raise newException(Exception, message)
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
    checkTypes(types),
    createTypes(dataType, enumName, types),
    createEqProc(dataType, types),
    createInitProcs(dataType, enumName, types),
    createCheckProc(dataType, types, attrs),
    createSessionProcs(dataType, types),
    createConstants(dataType, types, attrs)
  )

## staticRuleset

proc createTypesForSession(
    rulesSym: NimNode,
    enumSym: NimNode,
    rules: NimNode,
    ruleNameToTupleType: OrderedTable[string, NimNode],
    ruleNameToEnumItem: OrderedTable[string, NimNode]
  ): NimNode =
  var enumItems: seq[NimNode]
  for item in ruleNameToEnumItem.values:
    enumItems.add(item)
  let enumType = createVariantEnum(postfix(enumSym, "*"), enumItems)
  var cases = newNimNode(nnkRecCase)
  cases.add(newIdentDefs(postfix(ident("kind"), "*"), enumSym))
  for (ruleName, enumItem) in ruleNameToEnumItem.pairs:
    cases.add(createVariantBranch(enumItem, ident(ruleName), ruleNameToTupleType[ruleName]))
  result = newNimNode(nnkTypeSection)
  result.add(enumType)
  result.add(newNimNode(nnkTypeDef).add(
    postfix(rulesSym, "*"),
    newEmptyNode(), #newNimNode(nnkGenericParams),
    newNimNode(nnkObjectTy).add(
      newEmptyNode(),
      newEmptyNode(),
      newNimNode(nnkRecList).add(cases)
    )
  ))

proc getVarsFromRule(body: NimNode): seq[string] =
  expectKind(body, nnkStmtList)
  var t: Table[string, NimNode]
  for child in body:
    expectKind(child, nnkCall)
    let id = child[0]
    expectKind(id, nnkIdent)
    t[id.strVal] = child[1]
  for condition in t["what"]:
    for node in condition:
      if node.kind == nnkIdent:
        let s = node.strVal
        if s[0].isLowerAscii and not result.contains(s):
          result.add(s)

proc createTupleType(dataType: NimNode, vars: seq[string]): NimNode =
  var maybeType = newNimNode(nnkTupleTy)
  maybeType.add(newIdentDefs(ident("fact"), dataType))
  maybeType.add(newIdentDefs(ident("isSet"), ident("bool")))
  result = newNimNode(nnkTupleTy)
  for varName in vars:
    result.add(newIdentDefs(ident(varName), maybeType))

proc createCaseOfKeyGetters(ruleIdent: NimNode, objIdent: NimNode, keyIdent: NimNode, vars: seq[string]): NimNode =
  result = newNimNode(nnkCaseStmt)
  result.add(keyIdent)
  for varName in vars:
    let
      varIdent = ident(varName)
      branch = quote do:
        return `objIdent`.`ruleIdent`.`varIdent`.fact
    result.add(newNimNode(nnkOfBranch).add(varName.newLit, branch))
  let notFound = quote do:
    raise newException(Exception, "Key not found: " & `keyIdent`)
  result.add(newNimNode(nnkElse).add(notFound))

proc createCaseOfKeySetters(ruleIdent: NimNode, objIdent: NimNode, keyIdent: NimNode, valIdent: NimNode, vars: seq[string]): NimNode =
  result = newNimNode(nnkCaseStmt)
  result.add(keyIdent)
  for varName in vars:
    let
      varIdent = ident(varName)
      branch = quote do:
        `objIdent`.`ruleIdent`.`varIdent` = (fact: `valIdent`, isSet: true)
    result.add(newNimNode(nnkOfBranch).add(varName.newLit, branch))
  let notFound = quote do:
    raise newException(Exception, "Key not found: " & `keyIdent`)
  result.add(newNimNode(nnkElse).add(notFound))

proc createCaseOfKeyCheckers(ruleIdent: NimNode, objIdent: NimNode, keyIdent: NimNode, vars: seq[string]): NimNode =
  result = newNimNode(nnkCaseStmt)
  result.add(keyIdent)
  for varName in vars:
    let
      varIdent = ident(varName)
      branch = quote do:
        return `objIdent`.`ruleIdent`.`varIdent`.isSet
    result.add(newNimNode(nnkOfBranch).add(varName.newLit, branch))
  result.add(newNimNode(nnkElse).add(quote do: return false))

proc createGetterProc(
    dataType: NimNode,
    matchType: NimNode,
    ruleNameToVars: OrderedTable[string, seq[string]],
    ruleNameToEnumItem: OrderedTable[string, NimNode]
  ): NimNode =
  let
    procId = ident("[]")
    objIdent = ident("match")
    keyIdent = ident("key")
  var body = newNimNode(nnkCaseStmt)
  body.add(newDotExpr(objIdent, ident("kind")))
  for (ruleName, enumItem) in ruleNameToEnumItem.pairs:
    let branch = createCaseOfKeyGetters(ident(ruleName), objIdent, keyIdent, ruleNameToVars[ruleName])
    body.add(newNimNode(nnkOfBranch).add(enumItem, branch))
  newProc(
    name = postfix(procId, "*"),
    params = [
      dataType,
      newIdentDefs(objIdent, matchType),
      newIdentDefs(keyIdent, ident("string"))
    ],
    body = newStmtList(body)
  )

proc createSetterProc(
    dataType: NimNode,
    matchType: NimNode,
    ruleNameToVars: OrderedTable[string, seq[string]],
    ruleNameToEnumItem: OrderedTable[string, NimNode]
  ): NimNode =
  let
    procId = ident("[]=")
    objIdent = ident("match")
    keyIdent = ident("key")
    valIdent = ident("val")
  var body = newNimNode(nnkCaseStmt)
  body.add(newDotExpr(objIdent, ident("kind")))
  for (ruleName, enumItem) in ruleNameToEnumItem.pairs:
    let branch = createCaseOfKeySetters(ident(ruleName), objIdent, keyIdent, valIdent, ruleNameToVars[ruleName])
    body.add(newNimNode(nnkOfBranch).add(enumItem, branch))
  newProc(
    name = postfix(procId, "*"),
    params = [
      ident("void"),
      newIdentDefs(objIdent, newNimNode(nnkVarTy).add(matchType)),
      newIdentDefs(keyIdent, ident("string")),
      newIdentDefs(valIdent, dataType)
    ],
    body = newStmtList(body)
  )

proc createCheckerProc(
    dataType: NimNode,
    matchType: NimNode,
    ruleNameToVars: OrderedTable[string, seq[string]],
    ruleNameToEnumItem: OrderedTable[string, NimNode]
  ): NimNode =
  let
    procId = ident("hasKey")
    objIdent = ident("match")
    keyIdent = ident("key")
  var body = newNimNode(nnkCaseStmt)
  body.add(newDotExpr(objIdent, ident("kind")))
  for (ruleName, enumItem) in ruleNameToEnumItem.pairs:
    let branch = createCaseOfKeyCheckers(ident(ruleName), objIdent, keyIdent, ruleNameToVars[ruleName])
    body.add(newNimNode(nnkOfBranch).add(enumItem, branch))
  newProc(
    name = postfix(procId, "*"),
    params = [
      ident("bool"),
      newIdentDefs(objIdent, matchType),
      newIdentDefs(keyIdent, ident("string"))
    ],
    body = newStmtList(body)
  )

proc createInitMatchProc(matchType: NimNode, ruleNameToEnumItem: OrderedTable[string, NimNode]): NimNode =
  let ruleNameIdent = ident("ruleName")
  var body = newNimNode(nnkCaseStmt)
  body.add(ruleNameIdent)
  for (ruleName, enumItem) in ruleNameToEnumItem.pairs:
    let branch = quote do:
      `matchType`(kind: `enumItem`)
    body.add(newNimNode(nnkOfBranch).add(ruleName.newLit, branch))
  let notFound = quote do:
    raise newException(Exception, "Rule not found: " & `ruleNameIdent`)
  body.add(newNimNode(nnkElse).add(notFound))
  newProc(
    params = [
      matchType,
      newIdentDefs(ruleNameIdent, ident("string"))
    ],
    body = newStmtList(body)
  )

const matchTypeSuffix = "Match"

macro staticRuleset*(dataType: type, matchType: untyped, rules: untyped): untyped =
  when not defined(gcArc) and not defined(gcOrc):
    raise newException(Exception, "As of Nim 1.6.4, staticRuleset does not work with the default GC; you must use gc:arc or gc:orc")
  else:
    expectKind(matchType, {nnkIdent, nnkSym})
    var
      ruleNameToTupleType: OrderedTable[string, NimNode]
      ruleNameToEnumItem: OrderedTable[string, NimNode]
      ruleNameToVars: OrderedTable[string, seq[string]]
    let
      matchName = dataType.strVal & matchTypeSuffix
      # flatten rules if there are multiple levels of statement lists
      flatRules = newStmtList(flattenRules(rules))
    for rule in flatRules:
      let
        name = rule.getRuleName
        enumItem = genSym(nskEnumField, matchName & name)
        vars = getVarsFromRule(rule[2])
      ruleNameToTupleType[name] = createTupleType(dataType, vars)
      ruleNameToEnumItem[name] = enumItem
      ruleNameToVars[name] = vars
    let
      enumName = matchName & enumSuffix
      enumSym = genSym(nskType, enumName)
      typeNode = createTypesForSession(matchType, enumSym, flatRules, ruleNameToTupleType, ruleNameToEnumItem)
      getterProc = createGetterProc(dataType, matchType, ruleNameToVars, ruleNameToEnumItem)
      setterProc = createSetterProc(dataType, matchType, ruleNameToVars, ruleNameToEnumItem)
      checkerProc = createCheckerProc(dataType, matchType, ruleNameToVars, ruleNameToEnumItem)
      initMatchProc = createInitMatchProc(matchType, ruleNameToEnumItem)
    var tup = makeTupleOfRules(flatRules)
    for expr in tup:
      let rule = expr[1]
      expectKind(rule, nnkCommand)
      var call = rule[1]
      expectKind(call, nnkCall)
      call.add(matchType)
    let sessionSym = bindSym("initSession")
    var session = newNimNode(nnkCall).add(newNimNode(nnkBracketExpr).add(sessionSym, dataType, matchType))
    session.add(newNimNode(nnkExprEqExpr).add(ident("autoFire"), ident("autoFire")))
    session.add(newNimNode(nnkExprEqExpr).add(ident("initMatch"), initMatchProc))
    let autoFire = ident("autoFire")
    quote:
      `typeNode`
      `getterProc`
      `setterProc`
      `checkerProc`
      block:
        (initSession:
          proc (`autoFire`: bool = true): Session[`dataType`, `matchType`] =
            `session`
         ,
         rules: `tup`)

# a convenience macro that returns an instantiated session rather than an init proc
# prefer staticRuleset instead
macro initSessionWithRules*(dataType: type, args: varargs[untyped]): untyped =
  let
    matchName = dataType.strVal & matchTypeSuffix
    matchSym = genSym(nskType, matchName)
    argCount = args.len
    opts = args[0 ..< argCount-1]
    rules = args[argCount-1]
    initSession = genSym(nskLet, "initSession")
  var session = newNimNode(nnkCall).add(initSession)
  for opt in opts:
    expectKind(opt, nnkExprEqExpr)
    session.add(opt)
  quote:
    let (`initSession`, rules) = staticRuleset(`dataType`, `matchSym`, `rules`)
    var session = `session`
    for r in rules.fields:
      session.add(r)
    (session: session, rules: rules)

## export so the engine doesn't need to be imported directly

macro initSession*(dataType: type, autoFire: bool = true): untyped =
  quote do:
    initSession[`dataType`, Vars[`dataType`]](autoFire = `autoFire`)

export engine.Session, engine.fireRules, engine.add, engine.queryAll, engine.get, engine.unwrap

# i need to do this so users don't need to `import sets` explicitly
# see: https://github.com/nim-lang/Nim/issues/11167
export sets.items, sets.len, cows
