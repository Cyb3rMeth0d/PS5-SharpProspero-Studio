using System;
using SharpProspero.Application;
using SharpProspero.Graphics;
using SharpProspero.Interop.Pad;

namespace NeonArcade;

internal sealed class ArcadeApp : ProsperoApp
{
    private const int ItemCapacity = 12;
    private const float PlayerSpeed = 680f;

    private static readonly Color Ink = Color.FromRgb(0x09, 0x10, 0x18);
    private static readonly Color Panel = Color.FromRgb(0x13, 0x20, 0x2B);
    private static readonly Color Muted = Color.FromRgb(0x99, 0xAE, 0xBC);
    private static readonly Color Cyan = Color.FromRgb(0x51, 0xE0, 0xD0);
    private static readonly Color Pink = Color.FromRgb(0xFF, 0x6B, 0x8A);
    private static readonly Color Gold = Color.FromRgb(0xFF, 0xD1, 0x66);

    private static readonly string[] GameNames = ["PADDLE RUSH", "METEOR RUN", "STAR CATCHER"];
    private static readonly string[] GameDescriptions =
    [
        "Keep the ball in play and build your rally.",
        "Dodge the meteor field for as long as you can.",
        "Catch stars, avoid bombs, and chase a high score."
    ];

    private readonly FallingItem[] _items = new FallingItem[ItemCapacity];
    private int _selected;
    private int _game;
    private int _score;
    private int _best;
    private int _lives;
    private bool _playing;
    private bool _gameOver;
    private float _playerX;
    private float _playerY;
    private float _paddleX;
    private float _ballX;
    private float _ballY;
    private float _ballVelocityX;
    private float _ballVelocityY;
    private float _spawnTimer;
    private float _spawnInterval;
    private uint _randomState = 0xA341316C;

    protected override void OnFrame(FrameContext context)
    {
        Surface surface = context.Surface;
        int width = surface.Width;
        int height = surface.Height;
        float delta = Math.Clamp((float)context.DeltaSeconds, 0f, 0.05f);

        if (context.Pressed(ScePadButton.Options))
        {
            context.RequestExit();
            return;
        }

        if (!_playing)
        {
            if (context.Pressed(ScePadButton.Up))
                _selected = (_selected + GameNames.Length - 1) % GameNames.Length;
            if (context.Pressed(ScePadButton.Down))
                _selected = (_selected + 1) % GameNames.Length;
            if (context.Pressed(ScePadButton.Cross))
                StartGame(_selected, width, height);

            DrawMenu(surface, width, height);
            return;
        }

        if (context.Pressed(ScePadButton.Circle))
        {
            _playing = false;
            DrawMenu(surface, width, height);
            return;
        }

        if (_gameOver)
        {
            if (context.Pressed(ScePadButton.Cross))
                StartGame(_game, width, height);
            else
                DrawGame(surface, width, height);
            return;
        }

        switch (_game)
        {
            case 0:
                UpdatePaddle(context, width, height, delta);
                break;
            case 1:
                UpdateMeteorRun(context, width, height, delta);
                break;
            default:
                UpdateStarCatcher(context, width, height, delta);
                break;
        }

        DrawGame(surface, width, height);
    }

    private void StartGame(int game, int width, int height)
    {
        _game = game;
        _playing = true;
        _gameOver = false;
        _score = 0;
        _lives = 3;
        _playerX = width / 2f;
        _playerY = height * 0.72f;
        _paddleX = width / 2f;
        _ballX = width / 2f;
        _ballY = height * 0.4f;
        _ballVelocityX = 350f;
        _ballVelocityY = 410f;
        _spawnTimer = 0.2f;
        _spawnInterval = game == 1 ? 0.62f : 0.48f;

        for (int i = 0; i < _items.Length; i++)
            _items[i].Active = false;
    }

    private void UpdatePaddle(FrameContext context, int width, int height, float delta)
    {
        float paddleWidth = Math.Clamp(width * 0.16f, 150f, 270f);
        float paddleY = height - 112f;
        float direction = HorizontalDirection(context);
        _paddleX = Math.Clamp(_paddleX + direction * PlayerSpeed * delta, paddleWidth / 2f, width - paddleWidth / 2f);

        _ballX += _ballVelocityX * delta;
        _ballY += _ballVelocityY * delta;
        const float radius = 15f;

        if (_ballX < radius || _ballX > width - radius)
            _ballVelocityX = -_ballVelocityX;
        if (_ballY < 92f)
            _ballVelocityY = Math.Abs(_ballVelocityY);

        bool overlaps = _ballX >= _paddleX - paddleWidth / 2f && _ballX <= _paddleX + paddleWidth / 2f;
        if (_ballVelocityY > 0f && _ballY + radius >= paddleY && _ballY < paddleY + 28f && overlaps)
        {
            _ballY = paddleY - radius;
            _ballVelocityY = -Math.Abs(_ballVelocityY) * 1.035f;
            _ballVelocityX += ((_ballX - _paddleX) / (paddleWidth / 2f)) * 260f;
            _score++;
            _best = Math.Max(_best, _score);
        }

        if (_ballY - radius > height)
        {
            _lives--;
            if (_lives == 0)
            {
                _gameOver = true;
                return;
            }

            _ballX = width / 2f;
            _ballY = height * 0.4f;
            _ballVelocityX = _score % 2 == 0 ? 350f : -350f;
            _ballVelocityY = 410f;
        }
    }

    private void UpdateMeteorRun(FrameContext context, int width, int height, float delta)
    {
        MovePlayer(context, width, height, delta);
        _spawnTimer -= delta;
        if (_spawnTimer <= 0f)
        {
            SpawnItem(width, false);
            _spawnTimer = Math.Max(0.2f, _spawnInterval - _score * 0.003f);
        }

        for (int i = 0; i < _items.Length; i++)
        {
            if (!_items[i].Active)
                continue;

            _items[i].Y += _items[i].Speed * delta;
            if (Math.Abs(_items[i].X - _playerX) < 48f && Math.Abs(_items[i].Y - _playerY) < 48f)
            {
                _items[i].Active = false;
                LoseLife();
                continue;
            }

            if (_items[i].Y > height + 30f)
            {
                _items[i].Active = false;
                _score++;
                _best = Math.Max(_best, _score);
            }
        }
    }

    private void UpdateStarCatcher(FrameContext context, int width, int height, float delta)
    {
        float direction = HorizontalDirection(context);
        _playerX = Math.Clamp(_playerX + direction * PlayerSpeed * delta, 64f, width - 64f);
        float basketY = height - 112f;

        _spawnTimer -= delta;
        if (_spawnTimer <= 0f)
        {
            SpawnItem(width, NextRandom() % 5 == 0);
            _spawnTimer = Math.Max(0.22f, _spawnInterval - _score * 0.001f);
        }

        for (int i = 0; i < _items.Length; i++)
        {
            if (!_items[i].Active)
                continue;

            _items[i].Y += _items[i].Speed * delta;
            bool reachesBasket = _items[i].Y + 20f >= basketY && _items[i].Y - 20f <= basketY + 34f;
            if (reachesBasket && Math.Abs(_items[i].X - _playerX) < 72f)
            {
                _items[i].Active = false;
                if (_items[i].IsBomb)
                    LoseLife();
                else
                {
                    _score += 10;
                    _best = Math.Max(_best, _score);
                }
            }
            else if (_items[i].Y > height + 28f)
            {
                _items[i].Active = false;
            }
        }
    }

    private void MovePlayer(FrameContext context, int width, int height, float delta)
    {
        float x = HorizontalDirection(context);
        float y = VerticalDirection(context);
        _playerX = Math.Clamp(_playerX + x * PlayerSpeed * delta, 48f, width - 48f);
        _playerY = Math.Clamp(_playerY + y * PlayerSpeed * delta, height * 0.34f, height - 92f);
    }

    private void LoseLife()
    {
        _lives--;
        if (_lives <= 0)
        {
            _lives = 0;
            _gameOver = true;
        }
    }

    private void SpawnItem(int width, bool isBomb)
    {
        for (int i = 0; i < _items.Length; i++)
        {
            if (_items[i].Active)
                continue;

            _items[i].Active = true;
            _items[i].X = 54f + NextRandom() % (uint)Math.Max(1, width - 108);
            _items[i].Y = 48f;
            _items[i].Speed = 280f + Math.Min(_score * 5f, 360f);
            _items[i].IsBomb = isBomb;
            return;
        }
    }

    private uint NextRandom()
    {
        _randomState ^= _randomState << 13;
        _randomState ^= _randomState >> 17;
        _randomState ^= _randomState << 5;
        return _randomState;
    }

    private static float HorizontalDirection(FrameContext context)
    {
        float direction = 0f;
        if (context.Held(ScePadButton.Left)) direction--;
        if (context.Held(ScePadButton.Right)) direction++;
        return direction;
    }

    private static float VerticalDirection(FrameContext context)
    {
        float direction = 0f;
        if (context.Held(ScePadButton.Up)) direction--;
        if (context.Held(ScePadButton.Down)) direction++;
        return direction;
    }

    private void DrawMenu(Surface surface, int width, int height)
    {
        DrawBackground(surface, width, height);
        surface.DrawTextCentered("NEON ARCADE", 112, 7, Color.White);
        surface.DrawTextCentered("THREE QUICK GAMES. ONE HIGH SCORE.", 190, 2, Muted);

        int cardWidth = Math.Min(width - 100, 840);
        int cardHeight = Math.Clamp(height / 8, 82, 116);
        int gap = 18;
        int x = (width - cardWidth) / 2;
        int startY = height / 3;

        for (int i = 0; i < GameNames.Length; i++)
        {
            int y = startY + i * (cardHeight + gap);
            bool selected = i == _selected;
            surface.FillRoundedRect(x, y, cardWidth, cardHeight, 14, selected ? Color.FromRgb(0x1D, 0x38, 0x42) : Panel);
            surface.FillRoundedRect(x, y, selected ? 8 : 3, cardHeight, 3, selected ? Cyan : Color.FromRgb(0x37, 0x4A, 0x57));
            surface.DrawText(GameNames[i], x + 32, y + 26, 3, selected ? Color.White : Muted);
            surface.DrawText(GameDescriptions[i], x + 32, y + 65, 2, selected ? Cyan : Muted);
            surface.DrawText("0" + (i + 1), x + cardWidth - 62, y + 42, 3, selected ? Gold : Muted);
        }

        surface.DrawTextCentered("UP / DOWN  SELECT      CROSS  PLAY", height - 88, 2, Color.White);
        surface.DrawTextCentered("OPTIONS  EXIT", height - 54, 2, Muted);
    }

    private void DrawGame(Surface surface, int width, int height)
    {
        DrawBackground(surface, width, height);
        surface.DrawText(GameNames[_game], 52, 42, 4, Color.White);
        surface.DrawText("SCORE " + _score, 52, 94, 2, Cyan);
        surface.DrawText("BEST " + _best, 52, 126, 2, Muted);
        DrawLives(surface, width);

        switch (_game)
        {
            case 0:
                DrawPaddle(surface, width, height);
                break;
            case 1:
                DrawMeteorRun(surface, width, height);
                break;
            default:
                DrawStarCatcher(surface, width, height);
                break;
        }

        surface.DrawText("CIRCLE  MENU", 52, height - 48, 2, Muted);
        surface.DrawText("OPTIONS  EXIT", width - 220, height - 48, 2, Muted);
        if (_gameOver)
        {
            surface.FillRoundedRect(width / 2 - 260, height / 2 - 92, 520, 184, 18, Panel);
            surface.DrawTextCentered("ROUND OVER", height / 2 - 48, 5, Pink);
            surface.DrawTextCentered("CROSS  PLAY AGAIN", height / 2 + 12, 2, Color.White);
            surface.DrawTextCentered("CIRCLE  GAME MENU", height / 2 + 46, 2, Muted);
        }
    }

    private void DrawPaddle(Surface surface, int width, int height)
    {
        float paddleWidth = Math.Clamp(width * 0.16f, 150f, 270f);
        int paddleY = height - 112;
        surface.FillRoundedRect((int)(_paddleX - paddleWidth / 2f), paddleY, (int)paddleWidth, 26, 13, Cyan);
        surface.FillCircle((int)_ballX, (int)_ballY, 15, Gold);
        surface.DrawTextCentered("LEFT / RIGHT  MOVE", height - 92, 2, Muted);
    }

    private void DrawMeteorRun(Surface surface, int width, int height)
    {
        for (int i = 0; i < _items.Length; i++)
            if (_items[i].Active)
                surface.FillCircle((int)_items[i].X, (int)_items[i].Y, 22, Pink);

        surface.FillRoundedRect((int)_playerX - 28, (int)_playerY - 25, 56, 50, 12, Cyan);
        surface.FillRoundedRect((int)_playerX - 10, (int)_playerY - 34, 20, 18, 7, Color.White);
        surface.DrawTextCentered("ARROWS  DODGE", height - 92, 2, Muted);
    }

    private void DrawStarCatcher(Surface surface, int width, int height)
    {
        for (int i = 0; i < _items.Length; i++)
        {
            if (!_items[i].Active)
                continue;

            Color itemColor = _items[i].IsBomb ? Pink : Gold;
            surface.FillCircle((int)_items[i].X, (int)_items[i].Y, 18, itemColor);
            if (_items[i].IsBomb)
            {
                surface.FillRect((int)_items[i].X - 2, (int)_items[i].Y - 10, 4, 20, Ink);
                surface.FillRect((int)_items[i].X - 10, (int)_items[i].Y - 2, 20, 4, Ink);
            }
        }

        int basketY = height - 112;
        surface.FillRoundedRect((int)_playerX - 62, basketY, 124, 32, 10, Cyan);
        surface.FillRoundedRect((int)_playerX - 48, basketY - 12, 96, 12, 6, Color.White);
        surface.DrawTextCentered("LEFT / RIGHT  CATCH STARS", height - 92, 2, Muted);
    }

    private void DrawLives(Surface surface, int width)
    {
        for (int i = 0; i < _lives; i++)
            surface.FillCircle(width - 62 - i * 34, 58, 10, Pink);
    }

    private static void DrawBackground(Surface surface, int width, int height)
    {
        surface.FillVerticalGradient(0, 0, width, height, Ink, Color.FromRgb(0x0B, 0x1B, 0x24));
        surface.FillRect(0, height - 3, width, 3, Cyan);
    }

    private struct FallingItem
    {
        public bool Active;
        public bool IsBomb;
        public float X;
        public float Y;
        public float Speed;
    }
}

internal static class Program
{
    private static void Main()
    {
        using (var app = new ArcadeApp())
            app.Run();

        ProcessExit.Exit();
    }
}