import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';

class GameLogger {
  static final GameLogger _instance = GameLogger._internal();
  late File _logFile;
  bool _isInitialized = false;

  factory GameLogger() {
    return _instance;
  }

  GameLogger._internal();

  Future<void> initialize() async {
    if (!_isInitialized) {
      final directory = await _getGameDirectory();
      _logFile = File('${directory.path}/game_log.txt');
      
      if (await _logFile.exists()) {
        await _logFile.writeAsString(
          '\n\n=== НОВАЯ СЕССИЯ ИГРЫ ===\n${DateTime.now()}\n\n',
          mode: FileMode.append
        );
      } else {
        await _logFile.writeAsString('=== НАЧАЛО СЕССИИ ИГРЫ ===\n${DateTime.now()}\n\n');
      }
      
      _isInitialized = true;
    }
  }

  Future<void> log(String message) async {
    if (!_isInitialized) await initialize();

    try {
      final timestamp = DateTime.now().toString();
      await _logFile.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
      );
    } catch (e) {
      print('Ошибка записи в лог: $e');
    }
  }

  Future<void> logError(String context, dynamic error) async {
    await log('ОШИБКА: $context - $error');
  }

  Future<void> clearLog() async {
    if (!_isInitialized) await initialize();
    await _logFile.writeAsString('');
  }
}

class PlayerDataManager {
  static final PlayerDataManager _instance = PlayerDataManager._internal();
  late Directory _dataDirectory;

  factory PlayerDataManager() {
    return _instance;
  }

  PlayerDataManager._internal();

  Future<void> initialize() async {
    _dataDirectory = await _getGameDirectory();
  }

  Future<File> _getPlayerFile(String playerName) async {
    await initialize();
    final sanitizedName = playerName.replaceAll(
      RegExp(r'[^a-zA-Zа-яА-Я0-9]'),
      '_',
    );
    return File('${_dataDirectory.path}/player_$sanitizedName.json');
  }

  Future<Map<String, dynamic>> loadPlayerData(String playerName) async {
    try {
      final file = await _getPlayerFile(playerName);

      if (await file.exists()) {
        final content = await file.readAsString();
        return json.decode(content);
      } else {
        final initialData = {
          'name': playerName,
          'totalGames': 0,
          'wins': 0,
          'losses': 0,
          'created': DateTime.now().toIso8601String(),
          'lastPlayed': DateTime.now().toIso8601String(),
        };

        await savePlayerData(playerName, initialData);
        return initialData;
      }
    } catch (e) {
      GameLogger().logError('Ошибка загрузки данных игрока $playerName', e);
      return {
        'name': playerName,
        'totalGames': 0,
        'wins': 0,
        'losses': 0,
        'created': DateTime.now().toIso8601String(),
        'lastPlayed': DateTime.now().toIso8601String(),
      };
    }
  }

  Future<void> savePlayerData(
    String playerName,
    Map<String, dynamic> data,
  ) async {
    try {
      final file = await _getPlayerFile(playerName);
      data['lastPlayed'] = DateTime.now().toIso8601String();
      await file.writeAsString(json.encode(data));
    } catch (e) {
      GameLogger().logError('Ошибка сохранения данных игрока $playerName', e);
    }
  }

  Future<void> updateGameResult(String winnerName, String loserName) async {
    try {
      final winnerData = await loadPlayerData(winnerName);
      final loserData = await loadPlayerData(loserName);

      winnerData['totalGames'] = (winnerData['totalGames'] as int) + 1;
      winnerData['wins'] = (winnerData['wins'] as int) + 1;

      loserData['totalGames'] = (loserData['totalGames'] as int) + 1;
      loserData['losses'] = (loserData['losses'] as int) + 1;

      await savePlayerData(winnerName, winnerData);
      await savePlayerData(loserName, loserData);

      await GameLogger().log(
        'Обновлены данные игроков: $winnerName (победа), $loserName (поражение)',
      );
    } catch (e) {
      GameLogger().logError('Ошибка обновления результатов игры', e);
    }
  }
}

class CurrentGameManager {
  static final CurrentGameManager _instance = CurrentGameManager._internal();
  late File _gameFile;

  factory CurrentGameManager() {
    return _instance;
  }

  CurrentGameManager._internal();

  Future<void> initialize() async {
    final directory = await _getGameDirectory();
    _gameFile = File('${directory.path}/current_game.json');
  }

  Future<void> saveGameState(Map<String, dynamic> gameState) async {
    try {
      await initialize();
      await _gameFile.writeAsString(json.encode(gameState));
      await GameLogger().log('Сохранено состояние текущей игры');
    } catch (e) {
      GameLogger().logError('Ошибка сохранения состояния игры', e);
    }
  }

  Future<Map<String, dynamic>> loadGameState() async {
    try {
      await initialize();
      if (await _gameFile.exists()) {
        final content = await _gameFile.readAsString();
        if (content.trim().isEmpty) {
          return {};
        }
        return json.decode(content);
      }
    } catch (e) {
      GameLogger().logError('Ошибка загрузки состояния игры', e);
    }
    return {};
  }

  Future<void> clearGameState() async {
    try {
      await initialize();
      if (await _gameFile.exists()) {
        await _gameFile.writeAsString('');
        await GameLogger().log('Очищено состояние текущей игры');
      }
    } catch (e) {
      GameLogger().logError('Ошибка очистки состояния игры', e);
    }
  }

  Future<void> deleteGameFile() async {
    try {
      await initialize();
      if (await _gameFile.exists()) {
        await _gameFile.delete();
        await GameLogger().log('Удален файл текущей игры');
      }
    } catch (e) {
      GameLogger().logError('Ошибка удаления файла игры', e);
    }
  }

  Future<bool> hasSavedGame() async {
    await initialize();
    if (!await _gameFile.exists()) return false;
    final content = await _gameFile.readAsString();
    return content.trim().isNotEmpty;
  }
}

Future<Directory> _getGameDirectory() async {
  final directory = Directory('battleship_game_data');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

class BotAIIsolate {
  static Future<List<List<int>>> calculateBestMoves(
    GameBoard board,
    List<List<int>> possibleMoves,
    int maxMoves,
  ) async {
    final receivePort = ReceivePort();

    await Isolate.spawn(
      _calculateBestMovesIsolate,
      _IsolateData(receivePort.sendPort, board, possibleMoves, maxMoves),
    );

    return await receivePort.first;
  }

  static void _calculateBestMovesIsolate(_IsolateData data) {
    final board = data.board;
    final possibleMoves = data.possibleMoves;
    final maxMoves = data.maxMoves;

    List<List<int>> bestMoves = [];
    List<List<int>> huntMoves = [];
    List<List<int>> randomMoves = [];

    for (int i = 0; i < board.size; i++) {
      for (int j = 0; j < board.size; j++) {
        if (board.grid[i][j] == 'X') {
          final neighbors = [
            [i - 1, j],
            [i + 1, j],
            [i, j - 1],
            [i, j + 1],
          ];

          for (var neighbor in neighbors) {
            final x = neighbor[0], y = neighbor[1];
            if (x >= 0 && x < board.size && y >= 0 && y < board.size) {
              if (board.grid[x][y] != 'X' && board.grid[x][y] != '•') {
                if (!huntMoves.any((move) => move[0] == x && move[1] == y)) {
                  huntMoves.add([x, y]);
                }
              }
            }
          }
        }
      }
    }

    for (var move in possibleMoves) {
      if (huntMoves.any((hunt) => hunt[0] == move[0] && hunt[1] == move[1])) {
        bestMoves.add(move);
      } else {
        randomMoves.add(move);
      }
    }

    randomMoves.shuffle();

    bestMoves.addAll(randomMoves);

    if (bestMoves.length > maxMoves) {
      bestMoves = bestMoves.sublist(0, maxMoves);
    }

    data.sendPort.send(bestMoves);
  }
}

class _IsolateData {
  final SendPort sendPort;
  final GameBoard board;
  final List<List<int>> possibleMoves;
  final int maxMoves;

  _IsolateData(this.sendPort, this.board, this.possibleMoves, this.maxMoves);
}

String colorize(String text, String color) {
  const reset = '\x1B[0m';
  final colors = {
    'red': '\x1B[31m',
    'green': '\x1B[32m',
    'blue': '\x1B[34m',
    'yellow': '\x1B[33m',
    'gray': '\x1B[90m',
  };
  return '${colors[color] ?? ''}$text$reset';
}

class Ship {
  String name;
  int size;
  List<List<int>> coordinates;
  List<bool> hits;

  Ship(this.name, this.size)
    : coordinates = [],
      hits = List.filled(size, false);

  bool get isSunk => hits.every((hit) => hit);

  void addCoordinates(int x, int y) {
    coordinates.add([x, y]);
  }

  bool checkHit(int x, int y) {
    for (int i = 0; i < coordinates.length; i++) {
      if (coordinates[i][0] == x && coordinates[i][1] == y) {
        if (i < hits.length && !hits[i]) {
          hits[i] = true;
          return true;
        }
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'size': size,
      'coordinates': coordinates.map((coord) => coord.toList()).toList(),
      'hits': hits,
      'isSunk': isSunk,
    };
  }

  factory Ship.fromJson(Map<String, dynamic> json) {
    final ship = Ship(json['name'], json['size']);

    ship.coordinates = (json['coordinates'] as List)
        .map((coord) => List<int>.from(coord))
        .toList();

    ship.hits = List<bool>.from(json['hits']);
    return ship;
  }
}

class GameBoard {
  List<List<String>> grid;
  int size;
  List<Ship> ships;

  GameBoard(this.size)
    : grid = List.generate(size, (_) => List.filled(size, '~')),
      ships = [];

  bool placeShip(Ship ship, int x, int y, bool isHorizontal) {
    if (isHorizontal) {
      if (y + ship.size > size) return false;
      for (int i = 0; i < ship.size; i++) {
        if (grid[x][y + i] != '~') return false;
      }
    } else {
      if (x + ship.size > size) return false;
      for (int i = 0; i < ship.size; i++) {
        if (grid[x + i][y] != '~') return false;
      }
    }

    if (isHorizontal) {
      for (int i = 0; i < ship.size; i++) {
        grid[x][y + i] = 'O';
        ship.addCoordinates(x, y + i);
      }
    } else {
      for (int i = 0; i < ship.size; i++) {
        grid[x + i][y] = 'O';
        ship.addCoordinates(x + i, y);
      }
    }

    ships.add(ship);
    return true;
  }

  String attack(int x, int y) {
    if (grid[x][y] == 'X' || grid[x][y] == '•') {
      return 'already';
    }

    if (grid[x][y] == 'O') {
      for (Ship ship in ships) {
        if (ship.checkHit(x, y)) {
          grid[x][y] = 'X';
          if (ship.isSunk) {
            return 'sunk';
          }
          return 'hit';
        }
      }

      grid[x][y] = 'X';
      return 'hit';
    }

    if (grid[x][y] == '~') {
      grid[x][y] = '•';
      return 'miss';
    }

    return 'already';
  }

  void display(bool showShips) {
    stdout.write('  ');
    for (int i = 0; i < size; i++) {
      stdout.write('${String.fromCharCode(65 + i)} ');
    }
    print('');

    for (int i = 0; i < size; i++) {
      stdout.write('${i + 1} '.padLeft(2));
      for (int j = 0; j < size; j++) {
        String cell = grid[i][j];
        if (!showShips && cell == 'O') {
          stdout.write('~ ');
        } else {
          stdout.write('$cell ');
        }
      }
      print('');
    }
  }

  bool get allShipsSunk => ships.every((ship) => ship.isSunk);

  Map<String, dynamic> toJson() {
    return {
      'size': size,
      'grid': grid,
      'ships': ships.map((ship) => ship.toJson()).toList(),
    };
  }

  factory GameBoard.fromJson(Map<String, dynamic> json) {
    final board = GameBoard(json['size']);

    board.grid = (json['grid'] as List)
        .map((row) => List<String>.from(row))
        .toList();

    board.ships = (json['ships'] as List)
        .map((shipJson) => Ship.fromJson(shipJson))
        .toList();

    return board;
  }

  Map<String, dynamic> getGameStats(String playerName) {
    int hits = 0;
    int misses = 0;
    int shipsIntact = 0;
    int shipsDamaged = 0;
    int shipsSunk = 0;

    for (var ship in ships) {
      if (ship.isSunk) {
        shipsSunk++;
      } else if (ship.hits.any((hit) => hit)) {
        shipsDamaged++;
      } else {
        shipsIntact++;
      }
    }

    for (int i = 0; i < size; i++) {
      for (int j = 0; j < size; j++) {
        if (grid[i][j] == 'X') hits++;
        if (grid[i][j] == '•') misses++;
      }
    }

    return {
      'player': playerName,
      'hits': hits,
      'misses': misses,
      'shipsIntact': shipsIntact,
      'shipsDamaged': shipsDamaged,
      'shipsSunk': shipsSunk,
      'totalShips': ships.length,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}

class Player {
  String name;
  GameBoard board;
  bool isBot;
  Map<String, dynamic> playerData;

  Player(this.name, int boardSize, {this.isBot = false})
    : board = GameBoard(boardSize),
      playerData = {};

  Future<void> loadPlayerData() async {
    playerData = await PlayerDataManager().loadPlayerData(name);
  }

  Future<void> savePlayerData() async {
    await PlayerDataManager().savePlayerData(name, playerData);
  }

  Future<void> placeShipsManually(List<Ship> originalShips) async {
    List<Ship> ships = originalShips.map((s) => Ship(s.name, s.size)).toList();

    print('\n$name, размещение кораблей:');
    stdout.write('Хотите разместить корабли автоматически? (y/n): ');
    String? auto = stdin.readLineSync();

    if (auto != null && auto.toLowerCase() == 'y') {
      placeShipsAutomatically(ships);
      print('\nКорабли размещены автоматически!');
      board.display(true);
      return;
    }

    board.display(true);
    for (Ship ship in ships) {
      bool placed = false;
      while (!placed) {
        print('\nРазмещение корабля: ${ship.name} (размер: ${ship.size})');
        stdout.write('Введите координаты (например, A1): ');
        String? input = stdin.readLineSync();

        if (input == 'exit') exit(0);
        if (input == null || input.length < 2) {
          print('Неверный формат! Попробуйте снова.');
          continue;
        }

        try {
          int x = int.parse(input.substring(1)) - 1;
          int y = input[0].toUpperCase().codeUnitAt(0) - 65;

          if (x < 0 || x >= board.size || y < 0 || y >= board.size) {
            print('Координаты вне поля! Попробуйте снова.');
            await GameLogger().logError(
              'Игрок $name пытался разместить корабль на недопустимые координаты $input',
              'Координаты вне поля',
            );
            continue;
          }

          stdout.write('Горизонтально? (y/n): ');
          String? direction = stdin.readLineSync();
          bool isHorizontal = direction?.toLowerCase() == 'y';

          placed = board.placeShip(ship, x, y, isHorizontal);
          if (!placed) {
            print('Невозможно разместить корабль здесь! Попробуйте снова.');
            GameLogger().logError(
              'Игрок $name пытался разместить корабль на занятое поле $input',
              'Поле уже занято',
            );
          } else {
            print('Корабль размещен!');
            GameLogger().log(
              'Игрок $name разместил корабль ${ship.name} на $input',
            );
            board.display(true);
          }
        } catch (e) {
          print('Ошибка формата! Попробуйте снова.');
          GameLogger().logError(
            'Игрок $name ввел неверный формат координат: $input',
            e,
          );
        }
      }
    }
  }

  void placeShipsAutomatically(List<Ship> originalShips) {
    List<Ship> ships = originalShips.map((s) => Ship(s.name, s.size)).toList();
    Random random = Random();

    for (Ship ship in ships) {
      bool placed = false;
      while (!placed) {
        int x = random.nextInt(board.size);
        int y = random.nextInt(board.size);
        bool isHorizontal = random.nextBool();

        placed = board.placeShip(ship, x, y, isHorizontal);
      }
    }
    GameLogger().log('Игрок $name автоматически разместил корабли');
  }

  Future<bool> makeMove(GameBoard opponentBoard) async {
    print('\n$name, ваш ход!');

    print('\nВаше поле (слева) и поле противника (справа):');
    displayBothBoards(board, opponentBoard);

    bool turnContinues = true;
    bool gameOver = false;

    while (turnContinues && !gameOver) {
      bool validMove = false;
      while (!validMove) {
        stdout.write('Введите координаты для атаки (например, A1): ');
        String? input = stdin.readLineSync();

        if (input == 'exit') {
          exit(0);
        }

        if (input == null || input.length < 2) {
          print('Неверный формат! Попробуйте снова.');
          continue;
        }

        try {
          int x = int.parse(input.substring(1)) - 1;
          int y = input[0].toUpperCase().codeUnitAt(0) - 65;

          if (x < 0 ||
              x >= opponentBoard.size ||
              y < 0 ||
              y >= opponentBoard.size) {
            print('Координаты вне поля! Попробуйте снова.');
            await GameLogger().logError(
              'Игрок $name пытался атаковать недопустимые координаты $input',
              'Координаты вне поля',
            );
            continue;
          }

          String result = opponentBoard.attack(x, y);

          switch (result) {
            case 'hit':
              print('Попадание!');
              GameLogger().log('Игрок $name атаковал $input - ПОПАДАНИЕ');
              validMove = true;
              turnContinues = true;
              break;
            case 'sunk':
              print('Потоплен!');
              GameLogger().log(
                'Игрок $name атаковал $input - КОРАБЛЬ ПОТОПЛЕН',
              );
              validMove = true;
              turnContinues = true;
              break;
            case 'miss':
              print('Промах!');
              GameLogger().log('Игрок $name атаковал $input - ПРОМАХ');
              validMove = true;
              turnContinues = false;
              break;
            case 'already':
              print('Вы уже стреляли сюда! Попробуйте снова.');
              
              await GameLogger().logError(
                'Игрок $name пытался атаковать уже атакованное поле $input',
                'Поле уже атаковано',
              );
              break;
          }

          if (opponentBoard.allShipsSunk) {
            gameOver = true;
          }
        } catch (e) {
          print('Неверный формат! Попробуйте снова.');
          GameLogger().logError(
            'Игрок $name ввел неверный формат атаки: $input',
            e,
          );
        }
      }

      if (turnContinues && !gameOver) {
        print('\nПродолжайте ход!');
        print('\nТекущее состояние полей:');
        displayBothBoards(board, opponentBoard);
      }
    }

    print('\nРезультат после хода:');
    displayBothBoards(board, opponentBoard);

    return gameOver;
  }

  void displayBothBoards(GameBoard own, GameBoard enemy) {
    int size = own.size;

    int numberWidth = size >= 10 ? 2 : 1;

    String header =
        '  ' +
        List.generate(size, (i) => String.fromCharCode(65 + i)).join(' ') +
        ' ';

    stdout.write(' ' * numberWidth);
    stdout.write(header);
    stdout.write('   ');
    stdout.write(header);
    print('');

    String myFieldLabel = '--- МОЁ ПОЛЕ ---';
    String enemyFieldLabel = '--- ПОЛЕ ПРОТИВНИКА ---';
    int leftOffset = numberWidth + 1;
    int leftPadding = leftOffset + (header.length - myFieldLabel.length) ~/ 2;
    int rightPadding = (header.length - enemyFieldLabel.length) ~/ 2;

    stdout.write(' ' * leftPadding);
    stdout.write(myFieldLabel);
    stdout.write(
      ' ' *
          (header.length -
              myFieldLabel.length -
              (header.length - myFieldLabel.length) ~/ 2),
    );
    stdout.write('   ');
    stdout.write(' ' * rightPadding);
    stdout.write(enemyFieldLabel);
    print('');

    for (int i = 0; i < size; i++) {
      stdout.write('${(i + 1).toString().padLeft(numberWidth)} ');

      for (int j = 0; j < size; j++) {
        String cell = own.grid[i][j];
        String out = cell;
        if (cell == 'X')
          out = colorize('X', 'red');
        else if (cell == '•')
          out = colorize('•', 'blue');
        else if (cell == 'O')
          out = colorize('O', 'green');
        stdout.write('$out ');
      }

      stdout.write('   ');

      stdout.write('${(i + 1).toString().padLeft(numberWidth)} ');

      for (int j = 0; j < size; j++) {
        String cell = enemy.grid[i][j];
        String out = cell;
        if (cell == 'X')
          out = colorize('X', 'red');
        else if (cell == '•')
          out = colorize('•', 'blue');
        else
          out = '~';
        stdout.write('$out ');
      }
      print('');
    }

    print('\n=== Условные обозначения ===');
    print('${colorize("O", "green")} – ваш корабль');
    print('${colorize("X", "red")} – попадание');
    print('${colorize("•", "blue")} – промах');
    print('~ – пустая клетка (вода)');
  }

  Future<bool> makeBotMove(GameBoard opponentBoard) async {
    print('\n$name делает ход...');

    List<List<int>> possibleMoves = [];

    for (int i = 0; i < opponentBoard.size; i++) {
      for (int j = 0; j < opponentBoard.size; j++) {
        if (opponentBoard.grid[i][j] != 'X' &&
            opponentBoard.grid[i][j] != '•') {
          possibleMoves.add([i, j]);
        }
      }
    }

    if (possibleMoves.isEmpty) return opponentBoard.allShipsSunk;

    final bestMoves = await BotAIIsolate.calculateBestMoves(
      opponentBoard,
      possibleMoves,
      min(10, possibleMoves.length),
    );

    bool turnContinues = true;
    bool gameOver = false;

    for (var move in bestMoves) {
      if (!turnContinues || gameOver) break;

      int x = move[0];
      int y = move[1];

      String result = opponentBoard.attack(x, y);
      String coord = '${String.fromCharCode(65 + y)}${x + 1}';

      switch (result) {
        case 'hit':
          print('$name атаковал $coord - ${colorize("Попадание!", "red")}');
          GameLogger().log('Бот $name атаковал $coord - ПОПАДАНИЕ');
          turnContinues = true;
          break;
        case 'sunk':
          print(
            '$name атаковал $coord - ${colorize("Корабль потоплен!", "yellow")}',
          );
          GameLogger().log('Бот $name атаковал $coord - КОРАБЛЬ ПОТОПЛЕН');
          turnContinues = true;
          break;
        case 'miss':
          print('$name атаковал $coord - ${colorize("Промах!", "blue")}');
          GameLogger().log('Бот $name атаковал $coord - ПРОМАХ');
          turnContinues = false;
          break;
        case 'already':
          turnContinues = false;
          break;
      }

      if (opponentBoard.allShipsSunk) {
        gameOver = true;
      }

      if (!gameOver) {
        await Future.delayed(Duration(milliseconds: 500));
      }
    }
    return gameOver;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'isBot': isBot,
      'board': board.toJson(),
      'playerData': playerData,
    };
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    final player = Player(
      json['name'],
      json['board']['size'],
      isBot: json['isBot'],
    );
    player.board = GameBoard.fromJson(json['board']);
    player.playerData = Map<String, dynamic>.from(json['playerData']);
    return player;
  }
}

class BattleshipGame {
  List<Player> players = [];
  int boardSize;
  List<Ship> shipsTemplate = [];
  StreamController<String> _gameEventController =
      StreamController<String>.broadcast();
  bool _isLoadedGame = false;

  BattleshipGame(this.boardSize) {
    _setupShipsTemplate();
    _initializeGameEvents();
  }

  void _setupShipsTemplate() {
    switch (boardSize) {
      case 10:
        shipsTemplate = [
          Ship('Авианосец', 5),
          Ship('Линкор', 4),
          Ship('Крейсер', 3),
          Ship('Эсминец', 3),
          Ship('Подлодка', 2),
        ];
        break;
      case 14:
        shipsTemplate = [
          Ship('Авианосец', 5),
          Ship('Линкор', 4),
          Ship('Крейсер', 3),
          Ship('Крейсер', 3),
          Ship('Эсминец', 2),
          Ship('Эсминец', 2),
          Ship('Подлодка', 2),
        ];
        break;
      case 16:
        shipsTemplate = [
          Ship('Авианосец', 5),
          Ship('Линкор', 4),
          Ship('Линкор', 4),
          Ship('Крейсер', 3),
          Ship('Крейсер', 3),
          Ship('Эсминец', 2),
          Ship('Эсминец', 2),
          Ship('Подлодка', 2),
          Ship('Подлодка', 2),
        ];
        break;
    }
  }

  void _initializeGameEvents() {
    _gameEventController.stream.listen((event) {
      GameLogger().log('СОБЫТИЕ ИГРЫ: $event');
    });
  }

  void _addGameEvent(String event) {
    _gameEventController.add(event);
  }

  Future<void> setupNewGame() async {
    await GameLogger().initialize();

    print('=== МОРСКОЙ БОЙ ===');
    print('Размер поля: ${boardSize}x$boardSize');
    print('\nВыберите режим игры:');
    print('1. Игрок vs Игрок');
    print('2. Игрок vs Бот');
    stdout.write('Ваш выбор: ');

    String? choice = stdin.readLineSync();

    if (choice == 'exit') {
      exit(0);
    }

    bool vsBot = choice == '2';

    stdout.write('\nВведите имя первого игрока: ');
    String player1Name = stdin.readLineSync() ?? 'Игрок 1';
    final player1 = Player(player1Name, boardSize);
    await player1.loadPlayerData();
    players.add(player1);

    if (vsBot) {
      final bot = Player('Бот', boardSize, isBot: true);
      await bot.loadPlayerData();
      players.add(bot);
    } else {
      stdout.write('Введите имя второго игрока: ');
      String player2Name = stdin.readLineSync() ?? 'Игрок 2';
      final player2 = Player(player2Name, boardSize);
      await player2.loadPlayerData();
      players.add(player2);
    }

    _addGameEvent(
      'Начало НОВОЙ игры: ${players[0].name} vs ${players[1].name}',
    );

    for (Player player in players) {
      if (player.isBot) {
        player.placeShipsAutomatically(shipsTemplate);
        print('\n${player.name} разместил свои корабли.');
      } else {
        player.placeShipsManually(shipsTemplate);
      }
      _clearConsole();
    }

    await _saveGameState();
  }

  Future<void> startLoadedGame() async {
    await GameLogger().initialize();
    _addGameEvent(
      'ПРОДОЛЖЕНИЕ сохраненной игры: ${players[0].name} vs ${players[1].name}',
    );

    print('=== ПРОДОЛЖЕНИЕ СОХРАНЕННОЙ ИГРЫ ===');
    print('Игроки: ${players[0].name} vs ${players[1].name}');
    print('Размер поля: ${boardSize}x$boardSize');

    print('\nТекущее состояние игры:');
    players[0].displayBothBoards(players[0].board, players[1].board);
  }

  Future<void> startGame() async {
    if (!_isLoadedGame) {
      await setupNewGame();
    } else {
      await startLoadedGame();
    }

    int currentPlayerIndex = 0;
    bool gameOver = false;

    while (!gameOver) {
      Player currentPlayer = players[currentPlayerIndex];
      Player opponent = players[1 - currentPlayerIndex];

      if (!currentPlayer.isBot) {
        print('=== Ходит ${currentPlayer.name} ===');
      }

      bool won;

      if (currentPlayer.isBot) {
        won = await currentPlayer.makeBotMove(opponent.board);
      } else {
        won = await currentPlayer.makeMove(opponent.board);
      }

      await _saveGameState();

      if (won) {
        print('\n🎉 ${currentPlayer.name} победил! 🎉');
        _addGameEvent('Игра завершена. Победитель: ${currentPlayer.name}');

        await PlayerDataManager().updateGameResult(
          currentPlayer.name,
          opponent.name,
        );

        await _saveFinalGameStats(currentPlayer, opponent);

        gameOver = true;
      } else {
        if (!currentPlayer.isBot) {
          print('\nНажмите Enter для передачи хода...');
          stdin.readLineSync();
          _clearConsole();
        }
        currentPlayerIndex = 1 - currentPlayerIndex;
      }
    }

    await CurrentGameManager().clearGameState();

    await _showPlayerStats();
  }

  Future<void> _saveGameState() async {
    try {
      final gameState = {
        'boardSize': boardSize,
        'players': players.map((player) => player.toJson()).toList(),
        'shipsTemplate': shipsTemplate.map((ship) => ship.toJson()).toList(),
        'saveTime': DateTime.now().toIso8601String(),
      };

      await CurrentGameManager().saveGameState(gameState);
    } catch (e) {
      GameLogger().logError('Ошибка сохранения состояния игры', e);
    }
  }

  Future<void> _saveFinalGameStats(Player winner, Player loser) async {
    try {
      final gameStats = {
        'winner': winner.board.getGameStats(winner.name),
        'loser': loser.board.getGameStats(loser.name),
        'gameDuration': DateTime.now().toIso8601String(),
        'boardSize': boardSize,
      };

      final directory = await _getGameDirectory();
      final statsFile = File(
        '${directory.path}/game_stats_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await statsFile.writeAsString(json.encode(gameStats));

      GameLogger().log('Сохранена финальная статистика игры');
    } catch (e) {
      GameLogger().logError('Ошибка сохранения финальной статистики', e);
    }
  }

  Future<void> _showPlayerStats() async {
    print('\n=== СТАТИСТИКА ИГРОКОВ ===');

    for (Player player in players) {
      await player.loadPlayerData();
      final data = player.playerData;
      print('\n${player.name}:');
      print('  Всего игр: ${data['totalGames']}');
      print('  Побед: ${data['wins']}');
      print('  Поражений: ${data['losses']}');
      if (data['totalGames'] > 0) {
        final winRate = (data['wins'] / data['totalGames'] * 100)
            .toStringAsFixed(1);
        print('  Процент побед: $winRate%');
      }
      print(
        '  Последняя игра: ${DateTime.parse(data['lastPlayed']).toString()}',
      );
    }
  }

  void _clearConsole() {
    if (Platform.isWindows) {
      print('\x1B[2J\x1B[0;0H');
    } else {
      print('\x1B[2J\x1B[H');
    }
  }

  static Future<BattleshipGame?> loadGame() async {
    try {
      final hasSavedGame = await CurrentGameManager().hasSavedGame();
      if (!hasSavedGame) {
        print('Нет сохраненной игры для загрузки. Начата новая игра.');
        return null;
      }

      final gameState = await CurrentGameManager().loadGameState();
      if (gameState.isEmpty) {
        print('Файл сохранения пуст или поврежден.');
        return null;
      }

      final game = BattleshipGame(gameState['boardSize']);

      game.players = (gameState['players'] as List)
          .map((playerJson) => Player.fromJson(playerJson))
          .toList();

      game.shipsTemplate = (gameState['shipsTemplate'] as List)
          .map((shipJson) => Ship.fromJson(shipJson))
          .toList();

      game._isLoadedGame = true;

      await GameLogger().log('Загружена сохраненная игра');
      return game;
    } catch (e) {
      GameLogger().logError('Ошибка загрузки игры', e);
      print('Ошибка загрузки сохраненной игры: $e');
      return null;
    }
  }
}

void main() async {
  print('=== МОРСКОЙ БОЙ ===');
  print('1. Новая игра');
  print('2. Загрузить игру');
  stdout.write('Ваш выбор: ');

  String? choice = stdin.readLineSync();

  if (choice == 'exit') {
    exit(0);
  }

  BattleshipGame game;

  if (choice == '2') {
    game = await BattleshipGame.loadGame() ?? _createNewGame();
    if (game._isLoadedGame) {
      print('Игра загружена успешно!');
    }
  } else {
    game = _createNewGame();
  }

  await game.startGame();
}

BattleshipGame _createNewGame() {
  print('Выберите размер поля:');
  print('1. 10x10 (стандартный)');
  print('2. 14x14 (средний)');
  print('3. 16x16 (большой)');
  stdout.write('Ваш выбор: ');

  String? choice = stdin.readLineSync();

  if (choice == 'exit') {
    exit(0);
  }

  int boardSize;

  switch (choice) {
    case '1':
      boardSize = 10;
      break;
    case '2':
      boardSize = 14;
      break;
    case '3':
      boardSize = 16;
      break;
    default:
      boardSize = 10;
      print('Неверный выбор, используется стандартный размер 10x10');
  }

  return BattleshipGame(boardSize);
}
