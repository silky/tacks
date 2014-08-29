package actors

import scala.concurrent.duration._
import play.api.Play.current
import play.api.libs.concurrent.Akka
import play.api.libs.concurrent.Execution.Implicits._
import play.api.Logger
import akka.actor._
import org.joda.time.DateTime
import models._

case class PlayerLeaved(id: String)
case object UpdateLeaderboard
case object UpdateGusts

class RaceActor(race: Race) extends Actor {

  val playersStates = scala.collection.mutable.Map[String,BoatState]()
  val gusts = Seq[Gust]()
  var spells: Seq[Spell] = Spell.default
  var leaderboard = Seq[String]()

  Akka.system.scheduler.schedule(1.minute, 1.second, self, UpdateLeaderboard)
  Akka.system.scheduler.schedule(1.minute, 1.second, self, UpdateGusts)

  def receive = {
    case PlayerUpdate(id, state) => {
      playersStates.get(id) match {
        case Some(bs) => {
          if (bs.passedGates != state.passedGates) updateLeaderboard()
          bs.collisions(spells).map { spell =>
            spells = spells.filter(_ == spell) // Remove the spell from the game board
            playersStates.put(id, bs.copy(ownSpells = bs.ownSpells :+ spell)) // Add the spell to the player
          }
        }
        case None =>
      }
      playersStates += (id -> state)
      sender ! raceUpdateFor(id)
    }
    case PlayerLeaved(id) => {
      Logger.debug("Boat leaved: " + id)
      playersStates -= id
    }
    case UpdateLeaderboard => updateLeaderboard()
  }

  private def updateLeaderboard() =
    if (playersStates.values.exists(_.passedGates.nonEmpty)) {
      leaderboard = playersStates.toSeq.sortBy {
        case (_, b) => (- b.passedGates.length, b.passedGates.headOption)
      }.map(_._1)
    }

  private def raceUpdateFor(boatId: String) = {
    val bs = playersStates.get(boatId)
    RaceUpdate(
      now = DateTime.now,
      startTime = race.startTime,
      course = None, // already transmitted in initial update
      gusts = Seq(),
      opponents = playersStates.toSeq.filterNot(_._1 == boatId).map(_._2),
      leaderboard = leaderboard,
      availableSpells = spells,
      playerSpells = bs.map(_.ownSpells).getOrElse(Nil),
      triggeredSpells = bs.map(_.triggeredSpells).getOrElse(Nil)
    )
  }
}

object RaceActor {
  def props(race: Race) = Props(new RaceActor(race))
}




