import macros

macro iterateFields*(t: typed): untyped =
  echo "--------------------------------"

  # check type of t
  var tTypeImpl = t.getTypeImpl
  echo tTypeImpl.len
  echo tTypeImpl.kind
  echo tTypeImpl.typeKind
  echo tTypeImpl.treeRepr

  case tTypeImpl.typeKind:
  of ntyTuple:
    # For a tuple the IdentDefs are top level, no need to descent
    discard
  of ntyObject:
    # For an object we have to descent to the nnkRecList
    tTypeImpl = tTypeImpl[2]
  else:
    error "Not a tuple or object"

  # iterate over fields
  for child in tTypeImpl.children:
    if child.kind == nnkIdentDefs:
      let field = child[0] # first child of IdentDef is a Sym corresponding to field name
      let ftype = child[1] # second child is type
      echo "Iterating field: " & $field & " -> " & $ftype
    else:
      echo "Unexpected kind: " & child.kind.repr
      # Note that this can happen for an object with a case
      # fields, which would give a child of type nnkRecCase.
      # How to handle them depends on the use case.

