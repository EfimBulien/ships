import 'dart:io';
import 'dart:math';

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
    // Проверяем, не стреляли ли уже в эту клетку
    if (grid[x][y] == 'X' || grid[x][y] == '•') {
      return 'already';
    }

    // Проверяем попадание
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
      // Защита на случай, если 'O' не принадлежит ни одному кораблю
      // (не должно происходить при правильном размещении)
      grid[x][y] = 'X';
      return 'hit';
    }

    // Промах
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
}

class Player {
  String name;
  GameBoard board;
  bool isBot;

  Player(this.name, int boardSize, {this.isBot = false})
      : board = GameBoard(boardSize);

  void placeShipsManually(List<Ship> originalShips) {
    // Клонируем корабли, чтобы не использовать общие объекты
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
            continue;
          }

          stdout.write('Горизонтально? (y/n): ');
          String? direction = stdin.readLineSync();
          bool isHorizontal = direction?.toLowerCase() == 'y';

          placed = board.placeShip(ship, x, y, isHorizontal);
          if (!placed) {
            print('Невозможно разместить корабль здесь! Попробуйте снова.');
          } else {
            print('Корабль размещен!');
            board.display(true);
          }
        } catch (e) {
          print('Ошибка формата! Попробуйте снова.');
        }
      }
    }
  }

  void placeShipsAutomatically(List<Ship> originalShips) {
    // Клонируем корабли
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
  }

  bool makeMove(GameBoard opponentBoard) {
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
            continue;
          }

          String result = opponentBoard.attack(x, y);

          switch (result) {
            case 'hit':
              print('Попадание!');
              validMove = true;
              turnContinues = true;
              break;
            case 'sunk':
              print('Потоплен!');
              validMove = true;
              turnContinues = true;
              break;
            case 'miss':
              print('Промах!');
              validMove = true;
              turnContinues = false;
              break;
            case 'already':
              print('Вы уже стреляли сюда! Попробуйте снова.');
              break;
          }

          if (opponentBoard.allShipsSunk) {
            gameOver = true;
          }
        } catch (e) {
          print('Неверный формат! Попробуйте снова.');
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

    stdout.write('     ');
    for (int i = 0; i < size; i++) {
      stdout.write('${String.fromCharCode(65 + i)} ');
    }
    stdout.write('         ');
    for (int i = 0; i < size; i++) {
      stdout.write('${String.fromCharCode(65 + i)} ');
    }
    print('');

    print('   --- МОЁ ПОЛЕ ---             --- ПОЛЕ ПРОТИВНИКА ---');

    for (int i = 0; i < size; i++) {
      stdout.write('${(i + 1).toString().padLeft(2)} ');
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

      stdout.write('      ');

      stdout.write('${(i + 1).toString().padLeft(2)} ');
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

  bool makeBotMove(GameBoard opponentBoard) {
    print('\n$name делает ход...');

    List<List<int>> possibleMoves = [];

    for (int i = 0; i < opponentBoard.size; i++) {
      for (int j = 0; j < opponentBoard.size; j++) {
        if (opponentBoard.grid[i][j] != 'X' && opponentBoard.grid[i][j] != '•') {
          possibleMoves.add([i, j]);
        }
      }
    }

    if (possibleMoves.isEmpty) return opponentBoard.allShipsSunk;

    possibleMoves.shuffle();

    bool turnContinues = true;
    bool gameOver = false;

    while (turnContinues && !gameOver && possibleMoves.isNotEmpty) {
      List<int> move = possibleMoves.removeLast();
      int x = move[0];
      int y = move[1];

      String result = opponentBoard.attack(x, y);
      String coord = '${String.fromCharCode(65 + y)}${x + 1}';

      switch (result) {
        case 'hit':
          print('$name атаковал $coord - ${colorize("Попадание!", "red")}');
          turnContinues = true;
          break;
        case 'sunk':
          print(
            '$name атаковал $coord - ${colorize("Корабль потоплен!", "yellow")}',
          );
          turnContinues = true;
          break;
        case 'miss':
          print('$name атаковал $coord - ${colorize("Промах!", "blue")}');
          turnContinues = false;
          break;
        case 'already':
          // Не должно происходить, так как фильтруем выше
          turnContinues = false;
          break;
      }

      if (opponentBoard.allShipsSunk) {
        gameOver = true;
      }
    }
    return gameOver;
  }
}

class BattleshipGame {
  List<Player> players = [];
  int boardSize;
  List<Ship> shipsTemplate = [];

  BattleshipGame(this.boardSize) {
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

  void setupGame() {
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
    players.add(Player(player1Name, boardSize));

    if (vsBot) {
      players.add(Player('Бот', boardSize, isBot: true));
    } else {
      stdout.write('Введите имя второго игрока: ');
      String player2Name = stdin.readLineSync() ?? 'Игрок 2';
      players.add(Player(player2Name, boardSize));
    }

    for (Player player in players) {
      if (player.isBot) {
        player.placeShipsAutomatically(shipsTemplate);
        print('\n${player.name} разместил свои корабли.');
      } else {
        player.placeShipsManually(shipsTemplate);
      }
      _clearConsole();
    }
  }

  void startGame() {
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
        won = currentPlayer.makeBotMove(opponent.board);
      } else {
        won = currentPlayer.makeMove(opponent.board);
      }

      if (won) {
        print('\n🎉 ${currentPlayer.name} победил! 🎉');
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
  }

  void _clearConsole() {
    // Кроссплатформенная очистка
    if (Platform.isWindows) {
      print('\x1B[2J\x1B[0;0H'); // ANSI для Windows терминалов (новые)
    } else {
      print('\x1B[2J\x1B[H');
    }
  }
}

void main() {
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

  BattleshipGame game = BattleshipGame(boardSize);
  game.setupGame();
  game.startGame();
}