{-# LANGUAGE GADTs, GeneralizedNewtypeDeriving, RankNTypes, ScopedTypeVariables, TypeFamilies, TypeOperators #-}
module Control.Abstract.Evaluator
  ( Evaluator(..)
  , ValueRef(..)
  -- * Effects
  , Return(..)
  , earlyReturn
  , catchReturn
  , runReturn
  , LoopControl(..)
  , throwBreak
  , throwContinue
  , catchLoopControl
  , runLoopControl
  , module Control.Monad.Effect
  , module Control.Monad.Effect.Fail
  , module Control.Monad.Effect.Fresh
  , module Control.Monad.Effect.NonDet
  , module Control.Monad.Effect.Reader
  , module Control.Monad.Effect.Resumable
  , module Control.Monad.Effect.State
  , module Control.Monad.Effect.Trace
  ) where

import Control.Monad.Effect
import Control.Monad.Effect.Fail
import Control.Monad.Effect.Fresh
import Control.Monad.Effect.NonDet
import Control.Monad.Effect.Reader
import Control.Monad.Effect.Resumable
import Control.Monad.Effect.State
import Control.Monad.Effect.Trace
import Data.Abstract.Address
import Data.Abstract.FreeVariables
import Prologue

-- | An 'Evaluator' is a thin wrapper around 'Eff' with (phantom) type parameters for the location, term, and value types.
--
--   These parameters enable us to constrain the types of effects using them s.t. we can avoid both ambiguous types when they aren’t mentioned outside of the context, and lengthy, redundant annotations on the use sites of functions employing these effects.
--
--   These effects will typically include the environment, heap, module table, etc. effects necessary for evaluation of modules and terms, but may also include any other effects so long as they’re eventually handled.
newtype Evaluator location value effects a = Evaluator { runEvaluator :: Eff effects a }
  deriving (Applicative, Effectful, Functor, Monad)

deriving instance Member NonDet effects => Alternative (Evaluator location value effects)

-- | 'ValueRef' is the type subterms evaluate to and can represent either values directly ('Rval'), or references to values (lvals - such as local variables or object members)
data ValueRef location value where
  -- Represents a value:
  Rval :: Address location value -> ValueRef location value
  -- Represents a local variable. No environment is attached - it's assumed that LvalLocal will be evaluated in the same scope it was constructed:
  LvalLocal :: Name -> ValueRef location value
  -- Represents an object member:
  LvalMember :: Address location value -> Name -> ValueRef location value

  deriving (Eq, Ord, Show)

-- Effects

-- | An effect for explicitly returning out of a function/method body.
data Return value resume where
  Return :: value -> Return value value

deriving instance Eq value => Eq (Return value a)
deriving instance Show value => Show (Return value a)

earlyReturn :: Member (Return value) effects => value -> Evaluator location value effects value
earlyReturn = send . Return

catchReturn :: Member (Return value) effects => Evaluator location value effects a -> (forall x . Return value x -> Evaluator location value effects a) -> Evaluator location value effects a
catchReturn action handler = interpose pure (\ ret _ -> handler ret) action

runReturn :: Evaluator location value (Return value ': effects) value -> Evaluator location value effects value
runReturn = relay pure (\ (Return value) _ -> pure value)


-- | Effects for control flow around loops (breaking and continuing).
data LoopControl value resume where
  Break    :: value -> LoopControl value value
  Continue :: value -> LoopControl value value

deriving instance Eq value => Eq (LoopControl value a)
deriving instance Show value => Show (LoopControl value a)

throwBreak :: Member (LoopControl value) effects => value -> Evaluator location value effects value
throwBreak = send . Break

throwContinue :: Member (LoopControl value) effects => value -> Evaluator location value effects value
throwContinue = send . Continue

catchLoopControl :: Member (LoopControl value) effects => Evaluator location value effects a -> (forall x . LoopControl value x -> Evaluator location value effects a) -> Evaluator location value effects a
catchLoopControl action handler = interpose pure (\ control _ -> handler control) action

runLoopControl :: Evaluator location value (LoopControl value ': effects) value -> Evaluator location value effects value
runLoopControl = relay pure (\ eff _ -> case eff of
  Break    value -> pure value
  Continue value -> pure value)
