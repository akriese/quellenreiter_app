import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk.dart' as parse;
import 'package:parse_server_sdk_flutter/parse_server_sdk.dart';
import 'package:quellenreiter_app/models/player_relation.dart';
import 'package:quellenreiter_app/models/game.dart';
import 'package:quellenreiter_app/models/player.dart';
import 'package:quellenreiter_app/models/quellenreiter_app_state.dart';
import '../consonents.dart';
import '../constants/constants.dart';
import '../models/statement.dart';
import 'queries.dart';
import 'package:http/http.dart' as http;

/// This class facilitates the connection to the database and manages its
/// responses.
class DatabaseUtils {
  /// Holds any error message related to DB activity
  String? error;

  /// [GraphQLClient] client for the user database
  /// requires a token.
  GraphQLClient? userDatabaseClient;

  /// [GraphQLClient] for the statement database.
  /// Does not require a token.
  GraphQLClient statementDatabaseClient = GraphQLClient(
    cache: GraphQLCache(),
    link: HttpLink(statementDatabaseUrl, defaultHeaders: {
      'X-Parse-Application-Id': statementDatabaseApplicationID,
      'X-Parse-Client-Key': statementDatabaseClientKey,
    }),
  );

  /// Object to access [FlutterSecureStorage].
  var safeStorage = const FlutterSecureStorage();

  /// Live query livequery for games
  parse.LiveQuery? gameChangesLiveQuery;

  /// Live query livequery for friends
  parse.LiveQuery? newFriendsLiveQuery;

  /// Creates [userDatabaseClient].
  Future<bool> createUserDatabaseClient() async {
    // The session token.
    String? token = await safeStorage.read(key: "token");

    // If token is not null, check if it is valid.
    if (token != null) {
      // Link to user database.
      final HttpLink userDatabaseLink =
          HttpLink(userDatabaseUrl, defaultHeaders: {
        'X-Parse-Application-Id': userDatabaseApplicationID,
        'X-Parse-Client-Key': userDatabaseClientKey,
        'X-Parse-Session-Token': token,
      });

      // Provides data from server and facilitates requests.
      userDatabaseClient = GraphQLClient(
        cache: GraphQLCache(),
        link: userDatabaseLink,
      );
      return true;
    }
    return false;
  }

  /// Login a user.
  void login(String username, String password, Function loginCallback) async {
    // Link to server.
    final HttpLink httpLink = HttpLink(userDatabaseUrl, defaultHeaders: {
      'X-Parse-Application-Id': userDatabaseApplicationID,
      'X-Parse-Client-Key': userDatabaseClientKey,
      //'X-Parse-REST-API-Key' : kParseRestApiKey,
    });

    // Provides data from server and facilitates requests.
    GraphQLClient client = GraphQLClient(
      cache: GraphQLCache(),
      link: httpLink,
    );

    // The result returned from the query.
    var loginResult = await client.mutate(
      MutationOptions(
        document: gql(Queries.login(username, password)),
      ),
    );

    // If login result has any exceptions.
    if (loginResult.hasException) {
      _handleException(loginResult.exception!);
      loginCallback(null);
      return;
    }

    // Safe the new token.
    safeStorage.write(
        key: "token",
        value: loginResult.data?["logIn"]["viewer"]["sessionToken"]);

    loginCallback(
        LocalPlayer.fromMap(loginResult.data?["logIn"]["viewer"]["user"]));
    // Safe the User
  }

  /// Signup a user.
  ///
  // Emoji can not be safed while not authenticated.
  // 1. signup with username and password,
  // 2. create userdata with emoji and so on!
  // 3. turn on class protection on back4app.
  void signUp(String username, String password, String emoji,
      Function signUpCallback) async {
    //check for bad words
    bool isDirty = await containsBadWord(username);
    if (isDirty) {
      signUpCallback(null);
      return; //return if bad words are found
    }

    // Link to server.
    final HttpLink httpLink = HttpLink(userDatabaseUrl, defaultHeaders: {
      'X-Parse-Application-Id': userDatabaseApplicationID,
      'X-Parse-Client-Key': userDatabaseClientKey,
      //'X-Parse-REST-API-Key' : kParseRestApiKey,
    });

    // Provides data from server and facilitates requests.
    GraphQLClient client = GraphQLClient(
      cache: GraphQLCache(),
      link: httpLink,
    );

    // The result returned from the query.
    var signUpResult = await client.mutate(
      MutationOptions(
        document: gql(Queries.signUp(username, password, emoji)),
      ),
    );

    // If login result has any exceptions.
    if (signUpResult.hasException) {
      _handleException(signUpResult.exception!);

      signUpCallback(null);
      return;
    }

    // Safe the new token.
    await safeStorage.write(
        key: "token",
        value: signUpResult.data?["signUp"]["viewer"]["sessionToken"]);

    // parse player.
    var player =
        LocalPlayer.fromMap(signUpResult.data?["signUp"]["viewer"]["user"]);
    player.emoji = emoji;

    // upload emoji
    await createUserData(player, (p) => {player = p});

    signUpCallback(player);
  }

  /// Logsout a user by deleting the session token.
  Future<void> logout(Function logoutCallback) async {
    const safeStorage = FlutterSecureStorage();
    await safeStorage.delete(key: "token");

    // stop live queries
    if (gameChangesLiveQuery != null) {
      gameChangesLiveQuery!.client.disconnect();
      gameChangesLiveQuery = null;
    }

    if (newFriendsLiveQuery != null) {
      newFriendsLiveQuery!.client.disconnect();
      newFriendsLiveQuery = null;
    }

    // remove parse initialization
    userDatabaseClient = null;

    logoutCallback();
  }

  /// Checks if token is valid.
  Future<void> checkToken(Function checkTokenCallback) async {
    // The session token.
    String? token = await safeStorage.read(key: "token");

    // If token is not null, check if it is valid.
    if (token != null) {
      // Link to the database.
      final HttpLink httpLink = HttpLink(userDatabaseUrl, defaultHeaders: {
        'X-Parse-Application-Id': userDatabaseApplicationID,
        'X-Parse-Client-Key': userDatabaseClientKey,
        'X-Parse-Session-Token': token,
      });

      // The client that provides the connection.
      GraphQLClient client = GraphQLClient(
        cache: GraphQLCache(),
        link: httpLink,
      );

      // The query result.
      var queryResult = await client.query(QueryOptions(
        document: gql(Queries.getCurrentUser()),
      ));

      if (queryResult.hasException) {
        _handleException(queryResult.exception!);
        checkTokenCallback(null);
        return;
      } else {
        checkTokenCallback(
            LocalPlayer.fromMap(queryResult.data?["viewer"]["user"]));
        return;
      }
    }

    // no token, return false
    checkTokenCallback(null);
  }

  Future<Player> getUserData(Player p) async {
    if (!await createUserDatabaseClient()) {
      return p;
    }

    // The query result.
    var queryResult = await userDatabaseClient!.query(
      QueryOptions(
        document: gql(Queries.getUser()),
        variables: {"user": p.id},
      ),
    );

    if (queryResult.hasException) {
      _handleException(queryResult.exception!);

      return p;
    }
    return LocalPlayer.fromMap(queryResult.data!["user"]);
  }

  /// Get all friend requests.
  Future<PlayerRelationCollection?> getFriends(Player player) async {
    if (!await createUserDatabaseClient()) {
      return null;
    }

    // The query result.
    var queryResult = await userDatabaseClient!.query(
      QueryOptions(
        document: gql(Queries.getFriends(player)),
      ),
    );

    if (queryResult.hasException) {
      _handleException(queryResult.exception!);

      return null;
    } else {
      return PlayerRelationCollection.fromFriendshipMap(
          queryResult.data?["friendships"], player);
    }
  }

  /// Accept a friend request
  Future<void> acceptFriendRequest(
      Player p, PlayerRelation opp, Function acceptFriendCallback) async {
    if (!await createUserDatabaseClient()) {
      acceptFriendCallback(false);
      return;
    }

    // Update the friendship to be accepted by both players.
    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(Queries.updateFriendshipStatus(opp.friendshipId)),
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);

      acceptFriendCallback(false);
      return;
    } else {
      acceptFriendCallback(true);
      // update num of friends in Database.
      p.numFriends += 1;
      updateUserData(p, (Player? p) {});
      return;
    }
  }

  /// Get a single [Statement] from the Database by [Statement.objectId].
  Future<Statement?> getStatement(String statementID) async {
    var queryResult = await statementDatabaseClient.query(
      QueryOptions(document: gql(Queries.getStatement(statementID))),
    );
    if (queryResult.hasException) {
      _handleException(queryResult.exception!);

      return null;
    }
    return Statement.fromMap(queryResult.data?["statement"]);
  }

  /// Update a [LocalPlayer] in the Database by [String]. Only for username and
  /// device token! Thus only used for the logged in user.
  Future<void> updateUser(
      LocalPlayer player, Function updateUserCallback) async {
    // TODO fetch player before updating so nothing is overwritten
    // check username for bad words
    bool isDirty = await containsBadWord(player.name);
    if (isDirty) {
      updateUserCallback(null);
      return; //return if bad words are found
    }

    if (!await createUserDatabaseClient()) {
      await updateUserCallback(null);
      return;
    }

    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(Queries.updateUser()),
        variables: {
          "user": player.toUserMap(),
        },
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);

      await updateUserCallback(null);
      return;
    } else {
      await updateUserCallback(
          LocalPlayer.fromMap(mutationResult.data?["updateUser"]["user"]));
      return;
    }
  }

  /// Update a [Player]s userdata in the Database by [String].
  ///
  /// Can be anything except username and auth stuff.
  Future<void> updateUserData(
      Player player, Function updateUserCallback) async {
    // TODO: fetch player before updating so nothing is overwritten
    // The session token.

    if (!await createUserDatabaseClient()) {
      await updateUserCallback(null);
      return;
    }

    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(Queries.updateUserData()),
        variables: {
          "user": player.toUserDataMap(),
        },
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);

      await updateUserCallback(null);
    } else {
      await updateUserCallback(player
        ..updateDataWithMap(
            mutationResult.data?["updateUserData"]["userData"]));
    }
  }

  /// Create a [LocalPlayer]s userdata in the Database by [String].
  ///
  /// Can be anything except username and auth stuff.
  Future<void> createUserData(
      LocalPlayer player, Function createUserDataCallback) async {
    if (!await createUserDatabaseClient()) {
      createUserDataCallback(null);
      return;
    }

    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(Queries.updateUser()),
        variables: {
          "user": player.toUserMapWithNewUserData(),
        },
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);

      createUserDataCallback(null);
    } else {
      createUserDataCallback(
          LocalPlayer.fromMap(mutationResult.data?["updateUser"]["user"]));
    }
  }

  /// Update a [Friendship] in the Database by [String].
  Future<bool> updateFriendship(PlayerRelation _playerRelation) async {
    if (!await createUserDatabaseClient()) {
      return false;
    }

    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(Queries.updateFriendship()),
        variables: {
          "friendship": _playerRelation.toFriendshipMap(),
        },
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);

      return false;
    } else {
      return true;
    }
  }

  /// Update a [Game] in the Database by [String].
  ///
  /// Can be a new name or emoji.
  Future<bool> updateGame(QuellenreiterAppState appState) async {
    if (!await createUserDatabaseClient()) {
      return false;
    }

    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(Queries.updateGame()),
        variables: {
          "openGame": appState.focusedPlayerRelation!.openGame!.toMap(),
        },
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);

      return false;
    }

    // if game is finished, update the player and the game.
    if (appState.focusedPlayerRelation!.openGame!.gameFinished()) {
      // update friendship
      await updateFriendship(appState.focusedPlayerRelation!);
      // update player
      await updateUserData(appState.player!, (Player? p) {
        if (p != null) {
          appState.player = p;
        } else {
          appState.msg = "Player konnte nicht aktualisiert werden";
        }
      });
    }
    return true;
  }

  /// Upload a [Game] into the Database by [String].
  Future<Game?> uploadGame(PlayerRelation _playerRelation) async {
    if (!await createUserDatabaseClient()) {
      return null;
    }

    var temp = _playerRelation.openGame!.toMap();
    temp.remove("id");

    // ERROR HERE !!!!
    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(Queries.uploadGame()),
        variables: {
          "openGame": temp,
        },
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);

      return null;
    }

    Map<String, dynamic> openGame =
        mutationResult.data?["createOpenGame"][DbFields.friendshipOpenGame];
    return Game.fromDbMap(openGame, _playerRelation.playerIndex);
  }

  /// Fetch all safed/liked [Statements] from a [Player].
  Future<Statements?> getStatements(List<String> ids) async {
    var queryResult = await statementDatabaseClient.query(
      QueryOptions(
        document: gql(
          Queries.getStatements(),
        ),
        variables: {
          "ids": {
            "objectId": {"in": ids}
          }
        },
      ),
    );

    if (queryResult.hasException) {
      _handleException(queryResult.exception!);

      return null;
    }
    return Statements.fromMap(queryResult.data);
  }

  /// Authenticate a [Player] to get their emoji etc.
  Future<Player?> authenticate() async {
    return null;
  }

  Future<void> sendFriendRequest(QuellenreiterAppState appState,
      String playerRelationId, Function sendFriendRequestCallback) async {
    if (!await createUserDatabaseClient()) {
      sendFriendRequestCallback(false);
      return;
    }

    // Update the friendship to be accepted by both players.
    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(
            Queries.sendFriendRequest(appState.player!.id, playerRelationId)),
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);

      sendFriendRequestCallback(false);
    } else {
      sendFriendRequestCallback(true);
      sendPushFriendInvitation(appState, receiverId: playerRelationId);
    }
  }

  /// Search all Users to get new [PlayerRelationCollection].
  Future<void> searchFriends(String friendsQuery, List<String> friendNames,
      Function searchFriendsCallback) async {
    if (!await createUserDatabaseClient()) {
      searchFriendsCallback(false);
      return;
    }

    // The query result.
    var queryResult = await userDatabaseClient!.query(
      QueryOptions(
        document: gql(Queries.searchFriends(friendsQuery, friendNames)),
      ),
    );

    if (queryResult.hasException) {
      _handleException(queryResult.exception!);

      searchFriendsCallback(null);
    } else {
      searchFriendsCallback(
          PlayerRelationCollection.fromUserMap(queryResult.data?["users"]));
    }
  }

  /// Function to find and load nine statements that have not been played by either user.
  Future<List<String>?> getPlayableStatements(
      PlayerRelation _playerRelation, Player p) async {
    // combine played statements
    List<String> playedStatemntsCombined = [
      ..._playerRelation.opponent.playedStatements!,
      ...p.playedStatements!
    ];

    // get 50 possible ids
    var playableStatements = await statementDatabaseClient.query(
      QueryOptions(
        document: gql(Queries.getStatements()),
        variables: {
          "ids": {
            "objectId": {"notIn": playedStatemntsCombined}
          }
        },
      ),
    );

    // if exception in query, return null.
    if (playableStatements.hasException) {
      _handleException(playableStatements.exception!);

      return null;
    }

    // if not enough statements are accessible.
    if (playableStatements.data?["statements"]["edges"].length < 9) {
      error =
          "Es gibt nicht mehr genug Statements, die ihr beide noch nicht gespielt habt...";
      return null;
    }

    // choose 9 random statements
    //     playableStatements.data?["statements"]["edges"];
    List<String> ids = playableStatements.data?["statements"]["edges"]
        .map((el) => el!["node"]["objectId"].toString())
        .toList()
        .cast<String>();

    // random shuffling
    ids.shuffle();

    // add to played statements of p and e
    _playerRelation.opponent.playedStatements!.addAll(ids.take(9));
    p.playedStatements!.addAll(ids.take(9));

    //upload game game
    _playerRelation.openGame!.statementIds = ids.take(9).toList();
    _playerRelation.openGame = await uploadGame(_playerRelation);
    if (_playerRelation.openGame == null) {
      return null;
    }

    //update p and e in database
    await updateUserData(p, (Player? player) {});

    await updateUserData(_playerRelation.opponent, (Player? player) {});

    // update friendship
    await updateFriendship(_playerRelation);

    // updateUser(player, updateUserCallback)
    return ids.take(9).toList();
  }

  /// Function to delete a game in the database.
  Future<void> deleteGame(Game game) async {
    if (!await createUserDatabaseClient()) {
      return;
    }

    // Remeove the game
    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(Queries.removeGame()),
        variables: {
          "game": {
            "id": game.id,
          },
        },
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);
    }

    return;
  }

  Future<void> deleteAccount(QuellenreiterAppState appState) async {
    if (appState.player == null) {
      appState.route = Routes.login;
      return;
    }

    if (userDatabaseClient == null) {
      if (!await createUserDatabaseClient()) {
        appState.route = Routes.settings;
        return;
      }
    }

    // Remeove the User and all open games and friendships.
    var mutationResult = await userDatabaseClient!.mutate(
      MutationOptions(
        document: gql(Queries.deleteUser(appState)),
        variables: {
          "user": {
            "id": appState.player!.id,
          },
        },
      ),
    );

    if (mutationResult.hasException) {
      _handleException(mutationResult.exception!);
      appState.route = Routes.settings;

      return;
    }

    await safeStorage.delete(key: "token");

    // stop live queries
    if (gameChangesLiveQuery != null) {
      gameChangesLiveQuery!.client.disconnect();
      gameChangesLiveQuery = null;
    }

    if (newFriendsLiveQuery != null) {
      newFriendsLiveQuery!.client.disconnect();
      newFriendsLiveQuery = null;
    }

    appState.isLoggedIn = false;
    appState.route = Routes.login;
  }

  void startLiveQueryForFriends(QuellenreiterAppState appState) async {
    if (newFriendsLiveQuery != null) {
      newFriendsLiveQuery!.client.disconnect();
      newFriendsLiveQuery = null;
    }
    if (gameChangesLiveQuery != null) {
      gameChangesLiveQuery!.client.disconnect();
      gameChangesLiveQuery = null;
    }

    // Parse does not support live queries with relations.
    // Parse does not support graphql subscriptions ..
    await parse.Parse().initialize(userDatabaseApplicationID, userDatabaseUrl,
        clientKey: userDatabaseClientKey,
        debug: useDevServer,
        liveQueryUrl: userLiveQueryUrl,
        sessionId: await safeStorage.read(key: "token"),
        autoSendSessionId: true);

    newFriendsLiveQuery = parse.LiveQuery();

    // is user player 1?
    parse.QueryBuilder<parse.ParseObject> isPlayer1Query =
        parse.QueryBuilder<parse.ParseObject>(parse.ParseObject('Friendship'))
          ..whereEqualTo(DbFields.friendshipPlayer1Id, appState.player!.id);

    // is user player 2?
    parse.QueryBuilder<parse.ParseObject> isPlayer2Query =
        parse.QueryBuilder<parse.ParseObject>(parse.ParseObject('Friendship'))
          ..whereEqualTo(DbFields.friendshipPlayer2Id, appState.player!.id);

    parse.QueryBuilder<parse.ParseObject> mainQueryFriends =
        parse.QueryBuilder.or(
      parse.ParseObject("Friendship"),
      [isPlayer1Query, isPlayer2Query],
    );

    parse.Subscription subscriptionFriends =
        await newFriendsLiveQuery!.client.subscribe(mainQueryFriends);

    // called if new friendship is created
    subscriptionFriends.on(parse.LiveQueryEvent.create,
        (parse.ParseObject object) {
      if (appState.gameStarted) {
        return;
      }
      appState.getPlayerRelations();
    });

    //called if friendship is updated
    subscriptionFriends.on(parse.LiveQueryEvent.update,
        (parse.ParseObject object) {
      if (appState.gameStarted) {
        return;
      }
      appState.getPlayerRelations();
    });

    // find games that changed
    gameChangesLiveQuery = parse.LiveQuery();

    // is user player 1?
    parse.QueryBuilder<parse.ParseObject> isPlayer1QueryGame =
        parse.QueryBuilder<parse.ParseObject>(parse.ParseObject('Friendship'))
          ..whereEqualTo(DbFields.gamePlayer1Id, appState.player!.id);

    // is user player 2?
    parse.QueryBuilder<parse.ParseObject> isPlayer2QueryGame =
        parse.QueryBuilder<parse.ParseObject>(parse.ParseObject('Friendship'))
          ..whereEqualTo(DbFields.gamePlayer2Id, appState.player!.id);

    parse.QueryBuilder<parse.ParseObject> gameQuery = parse.QueryBuilder.or(
      parse.ParseObject("OpenGame"),
      [isPlayer1QueryGame, isPlayer2QueryGame],
    );

    parse.Subscription subscriptionGame =
        await gameChangesLiveQuery!.client.subscribe(gameQuery);

    // called if new game is created
    subscriptionGame.on(parse.LiveQueryEvent.create,
        (parse.ParseObject object) {
      // check if its players turn
      if (appState.gameStarted) {
        return;
      }
      appState.getPlayerRelations();
    });

    //called if game is updated
    subscriptionGame.on(parse.LiveQueryEvent.update,
        (parse.ParseObject object) {
      // parse game and find if its players turn
      if (appState.gameStarted) {
        return;
      }
      appState.getPlayerRelations();
    });
  }

  void sendPushFriendInvitation(QuellenreiterAppState appState,
      {String receiverId = "123"}) async {
    await parse.Parse().initialize(userDatabaseApplicationID,
        userDatabaseUrl.replaceAll("graphql", "parse"),
        clientKey: userDatabaseClientKey,
        debug: useDevServer,
        liveQueryUrl: userLiveQueryUrl,
        sessionId: await safeStorage.read(key: "token"),
        autoSendSessionId: true);

    //Executes a cloud function that returns a ParseObject type
    final ParseCloudFunction function =
        ParseCloudFunction('sendPushFriendRequest');

    final Map<String, dynamic> params = <String, dynamic>{
      'senderName': appState.player!.name,
      'receiverId': receiverId,
    };

    final ParseResponse parseResponse =
        await function.executeObjectFunction<ParseObject>(parameters: params);

    if (!parseResponse.success) {
      debugPrint("Push Failed");
    }
  }

  Future<bool> checkUsernameAlreadyExists(QuellenreiterAppState appState,
      {String username = "test"}) async {
    await parse.Parse().initialize(
      userDatabaseApplicationID,
      userDatabaseUrl.replaceAll("graphql", "parse"),
      clientKey: userDatabaseClientKey,
      debug: useDevServer,
      liveQueryUrl: userLiveQueryUrl,
    );

    //Executes a cloud function that returns a ParseObject type
    final ParseCloudFunction function = ParseCloudFunction('doesUsernameExist');
    final Map<String, dynamic> params = <String, dynamic>{
      'username': username,
    };

    final ParseResponse parseResponse =
        await function.execute(parameters: params);

    if (parseResponse.success) {
      var resultParsed = parseResponse.result == "true";
      //Transforms the return into a ParseObject
      return resultParsed;
    }

    error = "Error: ${parseResponse.error!.message}";
    return true;
  }

  void sendPushOtherPlayersTurn(QuellenreiterAppState appState,
      {String receiverId = "123"}) async {
    await parse.Parse().initialize(userDatabaseApplicationID,
        userDatabaseUrl.replaceAll("graphql", "parse"),
        clientKey: userDatabaseClientKey,
        debug: useDevServer,
        liveQueryUrl: userLiveQueryUrl,
        sessionId: await safeStorage.read(key: "token"),
        autoSendSessionId: true);

    //Executes a cloud function that returns a ParseObject type
    final ParseCloudFunction function =
        ParseCloudFunction('sendOtherPlayersTurn');

    final Map<String, dynamic> params = <String, dynamic>{
      'senderName': appState.player!.name,
      'receiverId': receiverId,
    };

    final ParseResponse parseResponse =
        await function.executeObjectFunction<ParseObject>(parameters: params);

    if (!parseResponse.success) {
      debugPrint("Push Failed");
    }
  }

  void sendPushOtherGameFinished(QuellenreiterAppState appState,
      {String receiverId = "123"}) async {
    await parse.Parse().initialize(userDatabaseApplicationID,
        userDatabaseUrl.replaceAll("graphql", "parse"),
        clientKey: userDatabaseClientKey,
        debug: useDevServer,
        liveQueryUrl: userLiveQueryUrl,
        sessionId: await safeStorage.read(key: "token"),
        autoSendSessionId: true);

    //Executes a cloud function that returns a ParseObject type
    final ParseCloudFunction function = ParseCloudFunction('sendGameFinished');
    final Map<String, dynamic> params = <String, dynamic>{
      'senderName': appState.player!.name,
      'receiverId': receiverId,
    };

    final ParseResponse parseResponse =
        await function.executeObjectFunction<ParseObject>(parameters: params);

    if (!parseResponse.success) {
      debugPrint("Push Failed");
    }
  }

  void sendPushGameStartet(QuellenreiterAppState appState,
      {String receiverId = "123"}) async {
    await parse.Parse().initialize(userDatabaseApplicationID,
        userDatabaseUrl.replaceAll("graphql", "parse"),
        clientKey: userDatabaseClientKey,
        debug: useDevServer,
        liveQueryUrl: userLiveQueryUrl,
        sessionId: await safeStorage.read(key: "token"),
        autoSendSessionId: true);

    //Executes a cloud function that returns a ParseObject type
    final ParseCloudFunction function =
        ParseCloudFunction('sendPushGameStartet');

    final Map<String, dynamic> params = <String, dynamic>{
      'senderName': appState.player!.name,
      'receiverId': receiverId,
    };

    final ParseResponse parseResponse =
        await function.executeObjectFunction<ParseObject>(parameters: params);

    if (!parseResponse.success) {
      debugPrint("Push Failed");
    }
  }

  /// Handle errors from GraphQL server.
  /// Todo: Move this into own class.
  void _handleException(OperationException e) {
    // errors in the database are not shown to the user
    if (e.graphqlErrors.isNotEmpty) {
      // handle graphql errors
      // set the error
      if (e.graphqlErrors[0].message == "Invalid username/password.") {
        error = "Falscher Username oder Passwort";
      }
      if (e.graphqlErrors[0].message ==
          "Account already exists for this username.") {
        error = "Der Username ist bereits vergeben";
      }
    } else if (e.linkException is NetworkException) {
      error = "Du bist offline...";
    } else if (e.linkException is ServerException) {
      error = "Du bist offline...";
    } else {
      error = "unbekannter Fehler. Versuche es erneut";
    }
  }

  Future<bool> containsBadWord(String username) async {
    if (username.isEmpty) {
      // return true because is empty
      error = "Username is empty";
      return true;
    }

    for (String s in customBadWords) {
      if (username.contains(s)) {
        error = "Username enthält ungültige Wörter.";
        return true;
      }
    }

    var url = Uri.https(
        badWordsUrl, "/text/", {'key': badWordsApiKey, 'msg': username});

    http.Response response = await http.get(url);

    if (response.statusCode == 200) {
      var jsonResponse = json.decode(response.body);
      if (jsonResponse['bad_words'].isNotEmpty) {
        error = "Username enthält ungültige Wörter";
        return true;
      } else {
        return false;
      }
    } else {
      error = "Server Error";
      return true;
    }
  }
}
