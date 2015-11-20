module StepTree where

import Debug
import Ansi.Log
import Array exposing (Array)
import Dict exposing (Dict)
import Focus exposing (Focus, (=>))

import BuildPlan exposing (BuildPlan)

type StepTree
  = Task Step
  | Get Step (Maybe Version)
  | Put Step
  | DependentGet Step
  | Aggregate (Array StepTree)
  | OnSuccess HookedStep
  | OnFailure HookedStep
  | Ensure HookedStep
  | Try StepTree
  | Timeout StepTree

type alias HookedStep =
  { step : StepTree
  , hook : StepTree
  }

type alias Step =
  { name : StepName
  , state : StepState
  , log : Ansi.Log.Window
  }

type alias StepName = String

type alias StepID = String

type alias Version = Dict String String

type StepState
  = StepStatePending
  | StepStateRunning
  | StepStateSucceeded
  | StepStateFailed
  | StepStateErrored

type alias StepFocus =
  Focus StepTree StepTree

type alias Root =
  { tree : StepTree
  , foci : Dict StepID StepFocus
  }

init : BuildPlan -> Root
init plan =
  case plan.step of
    BuildPlan.Task name ->
      initBottom Task plan.id name

    BuildPlan.Get name version ->
      initBottom (flip Get version) plan.id name

    BuildPlan.Put name ->
      initBottom Put plan.id name

    BuildPlan.DependentGet name ->
      initBottom DependentGet plan.id name

    BuildPlan.Aggregate plans ->
      let
        inited = Array.map init plans
        trees = Array.map .tree inited
        subFoci = Array.foldr Dict.union Dict.empty (Array.map .foci inited)
        wrappedFoci = Array.indexedMap (wrapAgg subFoci) plans
        foci = Dict.fromList (Array.toList wrappedFoci)
      in
        Root (Aggregate trees) foci

    BuildPlan.OnSuccess hookedPlan ->
      initHookedStep OnSuccess hookedPlan

    BuildPlan.OnFailure hookedPlan ->
      initHookedStep OnFailure hookedPlan

    BuildPlan.Ensure hookedPlan ->
      initHookedStep Ensure hookedPlan

    BuildPlan.Try plan ->
      initWrappedStep Try plan

    BuildPlan.Timeout plan ->
      initWrappedStep Timeout plan

initBottom : (Step -> StepTree) -> StepID -> StepName -> Root
initBottom create id name =
  let
    step =
      { name = name
      , state = StepStatePending
      , log = Ansi.Log.init
      }
  in
    { tree = create step
    , foci = Dict.singleton id (Focus.create identity identity)
    }

initWrappedStep : (StepTree -> StepTree) -> BuildPlan -> Root
initWrappedStep create plan =
  let
    {tree, foci} = init plan
  in
    { tree = create tree
    , foci = Dict.map wrapStep foci
    }

initHookedStep : (HookedStep -> StepTree) -> BuildPlan.HookedPlan -> Root
initHookedStep create hookedPlan =
  let
    stepRoot = init hookedPlan.step
    hookRoot = init hookedPlan.hook
  in
    { tree = create { step = stepRoot.tree, hook = hookRoot.tree }
    , foci = Dict.union
        (Dict.map wrapStep stepRoot.foci)
        (Dict.map wrapHook hookRoot.foci)
    }

wrapAgg : Dict StepID StepFocus -> Int -> BuildPlan -> (StepID, StepFocus)
wrapAgg subFoci i plan =
  case Dict.get plan.id subFoci of
    Nothing ->
      Debug.crash "welp"

    Just subFocus ->
      (plan.id, Focus.create (getAggIndex i) (setAggIndex i) => subFocus)

wrapStep : StepID -> StepFocus -> StepFocus
wrapStep id subFocus =
  Focus.create getStep updateStep => subFocus

getStep : StepTree -> StepTree
getStep tree =
  case tree of
    OnSuccess {step} ->
      step

    OnFailure {step} ->
      step

    Ensure {step} ->
      step

    Try step ->
      step

    Timeout step ->
      step

    _ ->
      Debug.crash "impossible"

updateStep : (StepTree -> StepTree) -> StepTree -> StepTree
updateStep update tree =
  case tree of
    OnSuccess hookedStep ->
      OnSuccess { hookedStep | step = update hookedStep.step }

    OnFailure hookedStep ->
      OnFailure { hookedStep | step = update hookedStep.step }

    Ensure hookedStep ->
      Ensure { hookedStep | step = update hookedStep.step }

    Try step ->
      Try (update step)

    Timeout step ->
      Timeout (update step)

    _ ->
      Debug.crash "impossible"

wrapHook : StepID -> StepFocus -> StepFocus
wrapHook id subFocus =
  Focus.create getHook updateHook => subFocus

getHook : StepTree -> StepTree
getHook tree =
  case tree of
    OnSuccess {hook} ->
      hook

    OnFailure {hook} ->
      hook

    Ensure {hook} ->
      hook

    _ ->
      Debug.crash "impossible"

updateHook : (StepTree -> StepTree) -> StepTree -> StepTree
updateHook update tree =
  case tree of
    OnSuccess hookedStep ->
      OnSuccess { hookedStep | hook = update hookedStep.hook }

    OnFailure hookedStep ->
      OnFailure { hookedStep | hook = update hookedStep.hook }

    Ensure hookedStep ->
      Ensure { hookedStep | hook = update hookedStep.hook }

    _ ->
      Debug.crash "impossible"

getAggIndex : Int -> StepTree -> StepTree
getAggIndex idx tree =
  case tree of
    Aggregate trees ->
      case Array.get idx trees of
        Just sub ->
          sub

        Nothing ->
          Debug.crash "impossible"

    _ ->
      Debug.crash "impossible"

setAggIndex : Int -> (StepTree -> StepTree) -> StepTree -> StepTree
setAggIndex idx update tree =
  case tree of
    Aggregate trees ->
      Aggregate (Array.set idx (update (getAggIndex idx tree)) trees)

    _ ->
      Debug.crash "impossible"
