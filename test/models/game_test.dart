import 'package:flutter_test/flutter_test.dart';
import 'package:quellenreiter_app/constants/constants.dart';
import 'package:quellenreiter_app/models/game.dart';

Map<String, dynamic> get mockGameMap {
  return {
    "id": "123456789",
    "fields": {
      DbFields.gamePlayer1Id: 123,
      DbFields.gamePlayer2Id: 456,
      DbFields.gameStatementIds: [1, 2, 3, 4, 5, 6, 7, 8, 9],
      DbFields.gameAnswersPlayer1: [true, true, false, false, true, false],
      DbFields.gameAnswersPlayer2: [true, false, true],
      DbFields.gameWithTimer: true,
      DbFields.gameRequestingPlayerIndex: 1,
      DbFields.gamePointsAccessed: false,
    }
  };
}

void main() {
  group("Testing GamePlayer class", () {
    // mock of a game map as returned from DB
    Map<String, dynamic> gameMap = mockGameMap;

    for (bool isFirstPlayer in [false, true]) {
      GamePlayer gamePlayer = GamePlayer.fromDbMap(gameMap, isFirstPlayer);

      test("GamePlayer.fromDbMap() should return a GamePlayer object", () {
        expect(gamePlayer, isA<GamePlayer>());
      });

      dynamic dbFields = gameMap["fields"];
      test(
          "GamePlayer.fromDbMap() should return a GamePlayer object with correct values",
          () {
        expect(
            gamePlayer.id,
            dbFields[isFirstPlayer
                ? DbFields.gamePlayer1Id
                : DbFields.gamePlayer2Id]);
        expect(
            gamePlayer.answers,
            dbFields[isFirstPlayer
                ? DbFields.gameAnswersPlayer1
                : DbFields.gameAnswersPlayer2]);
      });

      if (isFirstPlayer) {
        test("Check points for first player", () {
          expect(gamePlayer.getPoints(), 3);
        });
        test("Check amount of answered tasks for first player", () {
          expect(gamePlayer.amountAnswered, 6);
        });
      } else {
        test("Check correct points for second player", () {
          expect(gamePlayer.getPoints(), 2);
        });
        test("Check amount of answered tasks for first player", () {
          expect(gamePlayer.amountAnswered, 3);
        });
      }
    }
  });

  group("Test the Game class", () {
    // mock of a game map as returned from DB
    Map<String, dynamic> gameMap = mockGameMap;

    Game game = Game.fromDbMap(gameMap, 0);
  });
}
