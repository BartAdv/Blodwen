module Main

import Core.Binary
import Core.Context
import Core.Core
import Core.Directory
import Core.InitPrimitives
import Core.Options
import Core.Unify

import Idris.CommandLine
import Idris.Desugar
import Idris.ModTree
import Idris.Package
import Idris.Parser
import Idris.ProcessIdr
import Idris.REPL
import Idris.SetOptions
import Idris.Syntax

import Data.Vect
import System

import BlodwenPaths

%default covering

findInput : List CLOpt -> Maybe String
findInput [] = Nothing
findInput (InputFile f :: fs) = Just f
findInput (_ :: fs) = findInput fs

-- Add extra library directories from the "BLODWEN_PATH"
-- environment variable
updatePaths : {auto c : Ref Ctxt Defs} ->
              Core annot ()
updatePaths
    = do setPrefix bprefix
         defs <- get Ctxt
         bpath <- coreLift $ getEnv "BLODWEN_PATH"
         case bpath of
              Just path => do traverse addExtraDir (map trim (split (==':') path))
                              pure ()
              Nothing => pure ()
         bdata <- coreLift $ getEnv "BLODWEN_DATA"
         case bdata of
              Just path => do traverse addDataDir (map trim (split (==':') path))
                              pure ()
              Nothing => pure ()
         -- BLODWEN_PATH goes first so that it overrides this if there's
         -- any conflicts. In particular, that means that setting BLODWEN_PATH
         -- for the tests means they test the local version not the installed
         -- version
         addPkgDir "prelude"
         addPkgDir "base"
         addDataDir (dir_prefix (dirs (options defs)) ++ dirSep ++
                        "blodwen" ++ dirSep ++ "support")

updateREPLOpts : {auto c : Ref ROpts REPLOpts} ->
                 Core annot ()
updateREPLOpts
    = do opts <- get ROpts
         ed <- coreLift $ getEnv "EDITOR"
         case ed of
              Just e => put ROpts (record { editor = e } opts)
              Nothing => pure ()

stMain : List CLOpt -> Core FC ()
stMain opts
    = do c <- newRef Ctxt initCtxt
         s <- newRef Syn initSyntax
         addPrimitives

         updatePaths
         -- If there's a --build or --install, just do that then quit
         done <- processPackageOpts opts

         when (not done) $
            do preOptions opts

               let fname = findInput opts

               u <- newRef UST initUState
               o <- newRef ROpts (REPL.defaultOpts fname)

               updateREPLOpts
               case fname of
                    Nothing => readPrelude
                    Just f => updateErrorLine !(buildDeps f)

               doRepl <- postOptions opts
               if doRepl then
                    do putStrLnQ "Welcome to Blodwen. Good luck."
                       repl {c} {u}
                  else
                    -- exit with an error code if there was an error, otherwise
                    -- just exit
                    do ropts <- get ROpts
                       case errorLine ropts of
                            Nothing => pure ()
                            Just _ => coreLift $ exit 1

-- Run any options (such as --version or --help) which imply printing a
-- message then exiting. Returns wheter the program should continue
quitOpts : List CLOpt -> IO Bool
quitOpts [] = pure True
quitOpts (Version :: _) 
    = do putStrLn versionMsg
         pure False
quitOpts (Help :: _)
    = do putStrLn usage
         pure False
quitOpts (ShowPrefix :: _)
    = do putStrLn bprefix
         pure False
quitOpts (_ :: opts) = quitOpts opts

main : IO ()
main = do Right opts <- getCmdOpts
             | Left err =>
                    do putStrLn err
                       putStrLn usage
          continue <- quitOpts opts
          if continue
             then
                coreRun (stMain opts)
                     (\err : Error _ => 
                             do putStrLn ("Uncaught error: " ++ show err)
                                exit 1)
                     (\res => pure ())
             else pure ()

