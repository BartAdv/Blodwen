module Idris.Error

import Core.CaseTree
import Core.Core
import Core.Context
import Core.Options

import Idris.Resugar
import Idris.Syntax

import Parser.Support

%default covering

pshow : {auto c : Ref Ctxt Defs} ->
        {auto s : Ref Syn SyntaxInfo} ->
        Env Term vars -> Term vars -> Core FC String
pshow env tm 
    = do defs <- get Ctxt
         itm <- resugar env (normaliseHoles defs env tm)
         pure (show itm)

pshowNoNorm : {auto c : Ref Ctxt Defs} ->
        {auto s : Ref Syn SyntaxInfo} ->
        Env Term vars -> Term vars -> Core FC String
pshowNoNorm env tm 
    = do defs <- get Ctxt
         itm <- resugar env tm
         pure (show itm)

export
perror : {auto c : Ref Ctxt Defs} ->
         {auto s : Ref Syn SyntaxInfo} ->
         Error FC -> Core FC String
perror (Fatal err) = perror err
perror (CantConvert _ env l r)
    = pure $ "Mismatch between:\n\t" ++ !(pshow env l) ++ "\nand\n\t" ++ !(pshow env r)
perror (CantSolveEq _ env l r)
    = pure $ "Can't solve constraint between:\n\t" ++ !(pshow env l) ++ 
      "\nand\n\t" ++ !(pshow env r)
perror (Cycle _ env l r)
    = pure $ "Solving constraint between:\n\t" ++ !(pshow env l) ++ 
      "\nand\n\t" ++ !(pshow env r) ++ "\nwould lead to infinite value"
perror (WhenUnifying _ env x y err)
    = pure $ "When unifying " ++ !(pshow env x) ++ " and " ++ !(pshow env y) ++ "\n"
       ++ !(perror err)
perror (ValidCase _ env (Left tm))
    = pure $ !(pshow env tm) ++ " is not a valid impossible case"
perror (ValidCase _ env (Right err))
    = pure $ "Impossible pattern gives an error:\n" ++ !(perror err)
perror (UndefinedName _ x) = pure $ "Undefined name " ++ show x
perror (InvisibleName _ (NS ns x))
    = pure $ "Name " ++ show x ++ " is inaccessible since " ++
             showSep "." (reverse ns) ++ " is not explicitly imported"
perror (InvisibleName _ x)
    = pure $ "Name " ++ show x ++ " is inaccessible"
perror (BadTypeConType fc n)
    = pure $ "Return type of " ++ show n ++ " must be Type"
perror (BadDataConType fc n fam)
    = pure $ "Return type of " ++ show n ++ " must be in " ++ show fam
perror (LinearUsed fc count n)
    = pure $ "There are " ++ show count ++ " uses of linear name " ++ show n
perror (LinearMisuse fc n exp ctx)
    = pure $ show fc ++ ":Trying to use " ++ showRig exp ++ " name " ++ show n ++
                 " in " ++ showRel ctx ++ " context"
  where
    showRig : RigCount -> String
    showRig Rig0 = "irrelevant"
    showRig Rig1 = "linear"
    showRig RigW = "unrestricted"

    showRel : RigCount -> String
    showRel Rig0 = "irrelevant"
    showRel Rig1 = "relevant"
    showRel RigW = "non-linear"
perror (AmbiguousName fc ns) = pure $ "Ambiguous name " ++ show ns
perror (AmbiguousElab fc env ts)
    = do pp <- getPPrint
         setPPrint (record { fullNamespace = True } pp)
         let res = "Ambiguous elaboration. Possible correct results:\n\t" ++
                   showSep "\n\t" !(traverse (pshow env) ts)
         setPPrint pp
         pure res
perror (AmbiguousSearch fc env ts)
    = pure $ "Multiple solutions found in search. Possible correct results:\n\t" ++
           showSep "\n\t" !(traverse (pshowNoNorm env) ts)
perror (AllFailed ts)
    = case allUndefined ts of
           Just e => perror e
           _ => pure $ "Sorry, I can't find any elaboration which works. All errors:\n" ++
                     showSep "\n" !(traverse pAlterror ts)
  where
    pAlterror : (Maybe Name, Error FC) -> Core FC String
    pAlterror (Just n, err)
       = pure $ "If " ++ show n ++ ": " ++ !(perror err) ++ "\n"
    pAlterror (Nothing, err)
       = pure $ "Possible error:\n\t" ++ !(perror err)

    allUndefined : List (Maybe Name, Error FC) -> Maybe (Error FC)
    allUndefined [] = Nothing
    allUndefined [(_, UndefinedName loc e)] = Just (UndefinedName loc e)
    allUndefined ((_, UndefinedName _ e) :: es) = allUndefined es
    allUndefined _ = Nothing
perror (InvalidImplicit _ env n tm)
    = pure $ show n ++ " is not a valid implicit argument in " ++ !(pshow env tm)
perror (CantSolveGoal _ env g)
    = pure $ "Can't find an implementation for " ++ !(pshow env g)
perror (DeterminingArg _ n env g)
    = pure $ "Can't find an implementation for " ++ !(pshow env g) ++ "\n" ++
             "since I can't infer a value for argument " ++ show n
perror (UnsolvedHoles hs) 
    = pure $ "Unsolved holes:\n" ++ showHoles hs
  where
    showHoles [] = ""
    showHoles ((fc, n) :: hs) = show n ++ " introduced at " ++ show fc ++ "\n" 
                                       ++ showHoles hs
perror (CantInferArgType _ env n h ty)
    = pure $ "Can't infer type for argument " ++ show n ++ "\n" ++
             "Got " ++ !(pshow env ty) ++ " with hole " ++ show h
perror (SolvedNamedHole _ env h tm)
    = pure $ "Named hole " ++ show h ++ " has been solved by unification\n"
              ++ "Result: " ++ !(pshow env tm)
perror (VisibilityError fc vx x vy y)
    = pure $ show vx ++ " " ++ show (sugarName x) ++ 
             " cannot refer to " ++ show vy ++ " " ++ show (sugarName y)
perror (NonLinearPattern _ n) = pure $ "Non linear pattern " ++ show (sugarName n)
perror (BadPattern _ n) = pure $ "Pattern not allowed here"
perror (NoDeclaration _ n) = pure $ "No type declaration for " ++ show n
perror (AlreadyDefined _ n) = pure $ show n ++ " is already defined"
perror (NotFunctionType _ env tm)
    = pure $ !(pshow env tm) ++ " is not a function type"
perror (RewriteNoChange _ env rule ty)
    = pure $ "Rewriting by " ++ !(pshow env rule) ++ 
             " did not change type " ++ !(pshow env ty)
perror (NotRewriteRule fc env rule)
    = pure $ !(pshow env rule) ++ " is not a rewrite rule type"
perror (CaseCompile _ n DifferingArgNumbers)
    = pure $ "Patterns for " ++ show n ++ " have differing numbers of arguments"
perror (CaseCompile _ n DifferingTypes)
    = pure $ "Patterns for " ++ show n ++ " require matching on different types"
perror (CaseCompile _ n UnknownType)
    = pure $ "Can't infer type to match in " ++ show n
perror (BadDotPattern _ env reason x y)
    = pure $ "Can't match on " ++ !(pshow env x) ++
           (if reason /= "" then " (" ++ reason ++ ")" else "") ++ "\n" ++
           "It elaborates to: " ++ !(pshow env y)
perror (BadImplicit _ str) 
    = pure $ "Can't infer type for unbound implicit name " ++ str ++ "\n" ++
             "Try making it a bound implicit."
perror (BadRunElab _ env script)
    = pure $ "Bad elaborator script " ++ !(pshow env script)
perror (GenericMsg _ str) = pure str
perror (TTCError msg) = pure $ "Error in TTC file: " ++ show msg
perror (FileErr fname err) 
    = pure $ "File error in " ++ show fname ++ ": " ++ show err
perror (ParseFail err)
    = pure $ "Parse error: " ++ show err
perror (ModuleNotFound _ ns)
    = pure $ showSep "." (reverse ns) ++ " not found"
perror (CyclicImports ns)
    = pure $ "Module imports form a cycle: " ++ showSep " -> " (map showMod ns)
  where
    showMod : List String -> String
    showMod ns = showSep "." (reverse ns)
perror ForceNeeded = pure "Internal error when resolving implicit laziness"
perror (InternalError str) = pure $ "INTERNAL ERROR: " ++ str

perror (InType fc n err)
    = pure $ "While processing type of " ++ show (sugarName n) ++ 
             " at " ++ show fc ++ ":\n" ++ !(perror err)
perror (InCon fc n err)
    = pure $ "While processing constructor " ++ show (sugarName n) ++ 
             " at " ++ show fc ++ ":\n" ++ !(perror err)
perror (InLHS fc n err)
    = pure $ "While processing left hand side of " ++ show (sugarName n) ++ 
             " at " ++ show fc ++ ":\n" ++ !(perror err)
perror (InRHS fc n err)
    = pure $ "While processing right hand side of " ++ show (sugarName n) ++ 
             " at " ++ show fc ++ ":\n" ++ !(perror err)

export
display : {auto c : Ref Ctxt Defs} ->
          {auto s : Ref Syn SyntaxInfo} ->
          Error FC -> Core FC String
display err = pure $ maybe "" (\f => show f ++ ":") (getAnnot err) ++
                     !(perror err)
