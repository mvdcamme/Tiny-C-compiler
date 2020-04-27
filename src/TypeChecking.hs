module TypeChecking where

    import Data.List
    import Data.List.Extra
    import Debug
    import Debug.Trace
    import Text.Printf

    import AST
    import Environment
    import Type

    type TypeChecked t = Either String t
    type TypeResult = TypeChecked Type

    type UntypedBody              = Body ()
    type UntypedExp               = Expression ()
    type UntypedExps              = Expressions ()
    type UntypedLExp              = LeftExpression ()
    type UntypedStatement         = Statement ()
    type UntypedStatements        = Statements ()
    type UntypedDeclaration       = Declaration ()
    type UntypedDeclarations      = Declarations ()

    type TypedBody                = TypeChecked (Type, Body Type)
    type TypedExp                 = TypeChecked (Type, Expression Type)
    type TypedExps                = TypeChecked (Expressions Type)
    type TypedLExp                = TypeChecked (Type, LeftExpression Type)
    type TypedStatement           = TypeChecked (Type, Statement Type)
    type TypedStatements          = TypeChecked (Type, Statements Type)
    type TypedDeclaration         = TypeChecked (TypeEnvironment, Declaration Type)
    type TypedDeclarations        = TypeChecked (TypeEnvironment, Declarations Type)


    unknownVariableRefError :: Name -> TypeChecked a
    unknownVariableRefError var = error $ printf "Unknown variable %s" var

    isIntegralType :: Type -> TypeChecked Bool
    isIntegralType (Atom IntType) = return True
    isIntegralType (Atom CharType) = return True
    isIntegralType _ = return False

    isArrayType :: Type -> Bool
    isArrayType (ArrayType _ arrayElementType) = True
    isArrayType t = False

    equalsAtomicType :: AtomicType -> AtomicType -> Bool
    equalsAtomicType atomTyp1 atomTyp2 = case (atomTyp1, atomTyp2) of 
      (IntType, IntType) -> True
      (IntType, CharType) -> True
      (CharType, IntType) -> True
      (_, _) -> False

    equalsType :: Type -> Type -> Bool
    equalsType (Atom atomTyp1) (Atom atomTyp2) = equalsAtomicType atomTyp1 atomTyp2
    equalsType (ArrowType argTypes1 resultType1) (ArrowType argTypes2 resultType2) =
       (length argTypes1 == length argTypes2) &&
       (equalsType resultType1 resultType2) &&
       let zipped = zip argTypes1 argTypes2
           f = \(a, b) -> equalsType a b
       in all f zipped
    equalsType (ArrayType size1 resultType1) (ArrayType size2 resultType2) = (size1 == size2) && (resultType1 == resultType2) --  TODO

    typeOfArrayType :: Type -> TypeChecked Type
    typeOfArrayType (ArrayType _ arrayElementType) = return arrayElementType
    typeOfArrayType t = error $ printf "Type %s is not an array type" $ show t

    typeOfArrayRefExp :: TypeEnvironment -> UntypedExp -> UntypedExp -> TypedLExp
    typeOfArrayRefExp env arrayExp indexExp = do (arrayType, tArrayExp) <- typeCheckExp env arrayExp
                                                 arrayRefType <- typeOfArrayType arrayType
                                                 (indexType, tIndexExp) <- typeCheckExp env indexExp
                                                 -- TODO : check indexType is an integral type
                                                 let tArrayRefExp = ArrayRefExp tArrayExp tIndexExp arrayRefType
                                                 return (arrayRefType, tArrayRefExp)

    typeOfIntegralUnOp :: TypeEnvironment -> UnOperator -> UntypedExp -> TypedExp
    typeOfIntegralUnOp env unOp exp =
      do (expType, tExp) <- typeCheckExp env exp
         cond <- isIntegralType expType
         let unOpType = Atom IntType
         if cond
         then return $ (unOpType, UnaryExp unOp tExp unOpType)
         else error $ printf "%s expected integral type, received a %s instead" (show unOp) $ show tExp

    typeOfIntegralBinOp :: TypeEnvironment -> BinOperator -> UntypedExp -> UntypedExp -> (Type -> TypeChecked Bool) -> TypedExp
    typeOfIntegralBinOp env binOp exp1 exp2 pred =
      do (exp1Type, tExp1) <- typeCheckExp env exp1
         (exp2Type, tExp2) <- typeCheckExp env exp2
         cond1 <- isIntegralType exp1Type
         cond2 <- isIntegralType exp2Type
         let unOpType = Atom IntType
         if cond1 && cond2
         then return (unOpType, BinaryExp binOp tExp1 tExp2 unOpType)
         else error $ printf "%s expected integral types, received a %s and a %s instead" (show binOp) (show tExp1) $ show tExp2

    typeOfBinaryExp :: TypeEnvironment -> UntypedExp -> UntypedExp -> BinOperator -> TypedExp
    typeOfBinaryExp env exp1 exp2 binOp = typeOfIntegralBinOp env binOp exp1 exp2 isIntegralType

    expsMatchTypes :: TypeEnvironment -> UntypedExps -> [Type] -> TypedExps
    expsMatchTypes env exps types =
      Prelude.foldl (\prev curr -> let (exp, expectedType) = curr
                                   in do tExps <- prev
                                         (expType, tExp) <- typeCheckExp env exp
                                         if expType == expectedType
                                         then return (tExps `snoc` tExp)
                                         else fail $ printf "%s was expected to be of type %s; is of type %s instead" (show exp) (show tExp) (show expectedType))
                    (return []) $
                    zip exps types

    typeOfFunctionAppExp :: TypeEnvironment -> Name -> UntypedExps -> TypedExp
    typeOfFunctionAppExp env fName exps = case Environment.lookup fName env of
      Nothing -> unknownVariableRefError fName
      Just (ArrowType tArgs tResult) -> do tExps <- expsMatchTypes env exps tArgs
                                           let tExp = FunctionAppExp fName tExps tResult
                                           return (tResult, tExp)
      other -> error $ printf "Operator in function application has incorrect type: %s" $ show other

    typeOfLengthExp :: TypeEnvironment -> UntypedExp -> TypedExp
    typeOfLengthExp env exp = do (expType, tExp) <- typeCheckExp env exp
                                 if isArrayType expType
                                 then let typ = Atom IntType in return (typ, LengthExp tExp typ)
                                 else error $ printf "Length expected an array, received a %s" $ show tExp
      
    typeOfUnaryExp :: TypeEnvironment -> UntypedExp -> UnOperator -> TypedExp
    typeOfUnaryExp env exp unOp = typeOfIntegralUnOp env unOp exp

    typeOfUnaryModifyingExp :: TypeEnvironment -> UntypedLExp -> UnModifyingOperator -> TypedExp
    typeOfUnaryModifyingExp env lexp unOp =
      typeOfIntegralUnOp env (UnModifyingOperator unOp) (LeftExp lexp $ getLExpT lexp)

    typeOfVariableRefExp :: TypeEnvironment -> Name -> TypedLExp
    typeOfVariableRefExp env var = case Environment.lookup var env of
      Just t -> return (t, VariableRefExp var t)
      Nothing -> unknownVariableRefError var

    typeCheckLExp :: TypeEnvironment -> UntypedLExp -> TypedLExp
    typeCheckLExp env (ArrayRefExp array index _) = typeOfArrayRefExp env array index
    typeCheckLExp env (VariableRefExp var _) = typeOfVariableRefExp env var
    typeCheckLExp env (DerefExp lexp _) =
      do (lexpType, tLexp) <- typeCheckLExp env lexp
         case lexpType of
            PointerType pointedTo -> return (pointedTo, DerefExp tLexp pointedTo)
            _ -> error $ printf "Expression %s is not a pointer type" (show env)

    typeCheckExp :: TypeEnvironment -> UntypedExp -> TypedExp
    typeCheckExp env exp = case exp of
        NumberExp n _ -> let typ = Atom IntType in return (typ, NumberExp n typ)
        QCharExp c _ -> let typ = Atom CharType in return (typ, QCharExp c typ)
        BinaryExp binOp exp1 exp2 _ -> typeOfBinaryExp env exp1 exp2 binOp
        FunctionAppExp name exps _ -> typeOfFunctionAppExp env name exps
        LengthExp exp _ -> typeOfLengthExp env exp
        UnaryExp unOp exp _ -> typeOfUnaryExp env exp unOp
        UnaryModifyingExp unOp lexp _ -> typeOfUnaryModifyingExp env lexp unOp
        AddressOf lexp _ -> do (lexpType, tLexp) <- typeCheckLExp env lexp
                               let expType = PointerType lexpType
                               return (expType, AddressOf tLexp expType)
        LeftExp lexp _ -> do (lexpType, tLexp) <- typeCheckLExp env lexp
                             return (lexpType, LeftExp tLexp lexpType)

    void :: Type
    void = Atom VoidType

    typeCheckStatement :: TypeEnvironment -> UntypedStatement -> TypedStatement
    typeCheckStatement env (AssignStmt lexp exp _) = case lexp of
        VariableRefExp var _ -> do (varType, tVar) <- typeOfVariableRefExp env var
                                   (expType, tExp) <- typeCheckExp env exp
                                   let tLexp = VariableRefExp var varType
                                   if (expType == varType)
                                   then return (void, AssignStmt tLexp tExp void)
                                   else error $ printf "Assigning incorrect type %s to variable %s (of type %s)" (show tExp) var $ show expType
        ArrayRefExp array idx _ -> do (idxType, tIdx) <- typeCheckExp env idx
                                      (expType, tExp) <- typeCheckExp env exp
                                      (arrayExpType, tArrayExp) <- typeCheckExp env array
                                      if (idxType /= Atom IntType)
                                      then error $ printf "Incorrect type for the index-expression: expected Integral type, but is %s" $ show idxType
                                      else if (arrayExpType /= expType)
                                           then error $ printf "Assigning incorrect type %s to array-element of type %s" (show tExp) $ show tArrayExp
                                           else return (void, AssignStmt (ArrayRefExp tArrayExp tIdx arrayExpType) tExp void)
        DerefExp lexp _ -> do (lexpType, tLexp) <- typeCheckLExp env lexp
                              (expType, tExp) <- typeCheckExp env exp
                              case lexpType of
                                PointerType{} -> return (void, AssignStmt (DerefExp tLexp lexpType) tExp void)
                                _ -> error $ printf "Expression %s is not a pointer type" (show tLexp)
    typeCheckStatement env (BlockStmt block _) =
      do (blockType, tBlock) <- typeCheckBlock env block
         return (void, BlockStmt tBlock void)
    typeCheckStatement env (ExpStmt exp _) =
      do (expType, tExp) <- typeCheckExp env exp
         return (void, ExpStmt tExp void)
    typeCheckStatement env (ForStmt init m1 pred m2 inc m3 body m4 _) =
      do (_, tInit) <- typeCheckStatement env init
         (predType, tPred) <- typeCheckExp env pred
         isIntegral <- isIntegralType predType
         if isIntegral
         then return ()
         else error $ printf "Expression %s is not an integral type" (show pred)
         (_, tInc) <- typeCheckStatement env inc
         (_, tBody) <- typeCheckBlock env body
         return (void, ForStmt tInit m1 tPred m2 tInc m3 tBody m4 void)
    typeCheckStatement env (IfElseStmt pred thenBody m1 elseBody m2 _) =
      -- Type of the predicate can be everything: is not restricted to an integral type
      do (predType, tPred) <- typeCheckExp env pred
         (_, tThenBody) <- typeCheckBlock env thenBody
         (_, tElseBody) <- typeCheckBlock env elseBody
         return $ (void, IfElseStmt tPred tThenBody m1 tElseBody m2 void)
    typeCheckStatement env (IfStmt pred thenBody m1 _) =
      -- Type of the predicate can be everything: is not restricted to an integral type
      do (predType, tPred) <- typeCheckExp env pred
         (_, tThenBody) <- typeCheckBlock env thenBody
         return $ (void, IfStmt tPred tThenBody m1 void)
    typeCheckStatement env (Return0Stmt _) =
      -- should check whether function's return-type is void
      return (void, Return0Stmt void)
    typeCheckStatement env (Return1Stmt exp _) =
      -- should check whether matches function's return type
      do (expType, tExp) <- typeCheckExp env exp
         return (void, Return1Stmt tExp void)
    typeCheckStatement env (ReadStmt lexp _) =
      do (lexpType, tLexp) <- typeCheckLExp env lexp
         return (void, ReadStmt tLexp void)
    typeCheckStatement env (WriteStmt lexp _) =
      do (lexpType, tLexp) <- typeCheckLExp env lexp
         return (void, WriteStmt tLexp void)
    typeCheckStatement env (WhileStmt m1 pred body m2 _) =
      -- Should check that predType is an integral type?
      do (predType, tPred) <- typeCheckExp env pred
         (_, tBody) <- typeCheckBlock env body
         return (void, WhileStmt m1 tPred tBody m2 void)

    typeCheckStatements' :: TypeEnvironment -> UntypedStatements -> (Statements Type) -> TypedStatements
    typeCheckStatements' _ [] acc = return (void, acc)
    typeCheckStatements' env (stmt:stmts) acc =
      do (_, tStmt) <- typeCheckStatement env stmt
         typeCheckStatements' env stmts $ acc `snoc` tStmt

    typeCheckStatements :: TypeEnvironment -> UntypedStatements -> TypedStatements
    typeCheckStatements env stmts = typeCheckStatements' env stmts []

    declarationsToTypes :: UntypedDeclarations -> [Type]
    declarationsToTypes [] = []
    declarationsToTypes ((VarDeclaration typ _ _):decls) = typ : declarationsToTypes decls
    declarationsToTypes ((FunDeclaration retTyp _ parDecls _ _):decls) = (ArrowType (declarationsToTypes parDecls) retTyp) : declarationsToTypes decls

    -- typeCheckFunction :: TypeEnvironment -> Type -> UntypedDeclarations -> UntypedBody -> TypedBody
    -- typeCheckFunction env returnType pars body =
    --   -- Push new frame for the function's parameters
    --   let frameAddedEnv = Environment.push env
    --         -- Add parameters to the environment
    --   in do (updatedEnv, tDecls) <- typeCheckDeclarations' frameAddedEnv pars []
    --         -- Typecheck the function's body
    --         typeCheckBlock updatedEnv body

    typeCheckDeclaration :: TypeEnvironment -> UntypedDeclaration -> TypedDeclaration
    typeCheckDeclaration env (VarDeclaration typ name _) =
      let newEnv = Environment.insert name typ env
      in return (newEnv, VarDeclaration typ name void)
    typeCheckDeclaration env (FunDeclaration typ name decls body _) =
       -- Push new frame for the function's parameters
      let frameAddedEnv = Environment.push env
            -- Add parameters to the environment
      in do (updatedEnv, tDecls) <- typeCheckDeclarations' frameAddedEnv decls []
            -- Typecheck the function's body
            (_, tBody) <- typeCheckBlock updatedEnv body
            -- Insert the function declaration into the _original_ environment
            let newEnv = Environment.insert name (ArrowType (declarationsToTypes decls) typ) env
            return (newEnv, FunDeclaration typ name tDecls tBody void)

    typeCheckDeclarations' :: TypeEnvironment -> UntypedDeclarations -> (Declarations Type) -> TypedDeclarations
    typeCheckDeclarations' env [] acc = return (env, acc)
    typeCheckDeclarations' env (decl:decls) acc =
      do (updatedEnv, tDecl) <- typeCheckDeclaration env decl
         typeCheckDeclarations' updatedEnv decls $ acc `snoc` tDecl

    typeCheckDeclarations :: UntypedDeclarations -> TypedDeclarations
    typeCheckDeclarations decls =
      let emptyEnv = Environment.empty
          initEnv = Environment.insert "print" (ArrowType [Atom IntType] $ Atom VoidType) emptyEnv 
      in typeCheckDeclarations' initEnv decls []

    typeCheckBlock' :: TypeEnvironment -> UntypedBody -> Body Type -> TypedBody
    typeCheckBlock' _ (Body [] [] _) accBody = return (void, accBody)
    typeCheckBlock' env (Body decls stmts _) (Body tDecls tSmts _)  =
      do (updatedEnv, tDecls) <- typeCheckDeclarations' env decls []
         (_, tStmts) <- typeCheckStatements updatedEnv stmts
         return (void, Body tDecls tStmts void)

    typeCheckBlock :: TypeEnvironment -> UntypedBody -> TypedBody
    typeCheckBlock env body =
      let frameAddedEnv = Environment.push env
          emptyTypedBody = Body [] [] void
      in typeCheckBlock' frameAddedEnv body emptyTypedBody
