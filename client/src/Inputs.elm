module Inputs where

import Signal exposing (..)
import Time exposing (..)
import List as L
import Set as S exposing (..)
import Keyboard
import Char
import Json.Decode as Json exposing (..)
import Task exposing (Task, andThen)
import Http

import Game exposing (..)
import State exposing (..)
import Geo exposing (Point)
import Forms.Model as Forms
import Decoders exposing (raceCourseStatusDecoder, playerDecoder)
import ServerApi


type alias AppInput =
  { action : Action
  , clock: Clock
  }


-- Actions

type Action
  = NoOp
  | GameUpdate GameInput
  | LiveUpdate LiveStatus
  | PlayerUpdate Player
  | Navigate Screen
  | FormAction Forms.UpdateForm

actionsMailbox : Signal.Mailbox Action
actionsMailbox =
  Signal.mailbox NoOp

navigate : Screen -> Message
navigate screen =
  Signal.message actionsMailbox.address (Navigate screen)

-- LiveCenter

runServerUpdate : Task Http.Error ()
runServerUpdate =
  (Task.map LiveUpdate ServerApi.getLiveStatus)
    `Task.andThen` (Signal.send actionsMailbox.address)


-- Game

type alias GameInput =
  { clock : Clock
  , keyboardInput : KeyboardInput
  , windowInput : (Int,Int)
  , raceInput : RaceInput
  }

type alias Clock =
  { delta : Float
  , time : Float
  }

type alias KeyboardInput =
  { arrows : UserArrows
  , lock : Bool
  , tack : Bool
  , subtleTurn : Bool
  , startCountdown : Bool
  , escapeRun : Bool
  }

emptyKeyboardInput : KeyboardInput
emptyKeyboardInput =
  { arrows = { x = 0, y = 0 }
  , lock = False
  , tack = False
  , subtleTurn = False
  , startCountdown = False
  , escapeRun = False
  }

type alias UserArrows = { x : Int, y : Int }

type alias RaceInput =
  { serverNow:   Time
  , startTime:   Maybe Time
  , wind:        Game.Wind
  , opponents:   List Game.Opponent
  , ghosts:      List Game.GhostState
  , leaderboard: List Game.PlayerTally
  , initial:     Bool
  , clientTime:  Time
  }

initialRaceInput : RaceInput
initialRaceInput =
  { serverNow = 0
  , startTime = Nothing
  , wind = defaultWind
  , opponents = []
  , ghosts = []
  , leaderboard = []
  , initial = True
  , clientTime = 0
  }


extractGameUpdate : Clock -> KeyboardInput -> (Int,Int) -> Maybe RaceInput -> Maybe Action
extractGameUpdate clock keyboardInput dims maybeRaceInput =
  Maybe.map (GameInput clock keyboardInput dims) maybeRaceInput
    |> Maybe.map GameUpdate


manualTurn ki = ki.arrows.x /= 0
isTurning ki = manualTurn ki && not ki.subtleTurn
isSubtleTurning ki = manualTurn ki && ki.subtleTurn
isLocking ki = ki.arrows.y > 0 || ki.lock

toKeyboardInput : UserArrows -> Set Keyboard.KeyCode -> KeyboardInput
toKeyboardInput arrows keys =
  { arrows = arrows
  , lock = S.member 13 keys
  , tack = S.member 32 keys
  , subtleTurn = S.member 16 keys
  , startCountdown = S.member (Char.toCode 'C') keys
  , escapeRun = S.member 27 keys
  }

keyboardInput : Signal KeyboardInput
keyboardInput = Signal.map2 toKeyboardInput
  Keyboard.arrows
  Keyboard.keysDown


