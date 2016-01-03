module Screens.UpdateUtils where

import Effects exposing (Effects)
import TransitRouter

import Routes
import AppTypes exposing (appActionsAddress)
import Models exposing (..)


redirect : Routes.Route -> Effects ()
redirect route =
  Routes.toPath route
    |> Signal.send TransitRouter.pushPathAddress
    |> Effects.task

setPlayer : Player -> Effects ()
setPlayer player =
  AppTypes.SetPlayer player
    |> Signal.send appActionsAddress
    |> Effects.task

always : action -> Effects a -> Effects action
always action effect =
  Effects.map (\_ -> action) effect

screenAddr : (action -> AppTypes.ScreenAction) -> Signal.Address action
screenAddr toScreenAction =
  Signal.forwardTo appActionsAddress (toScreenAction >> AppTypes.ScreenAction)
