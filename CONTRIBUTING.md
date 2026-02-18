# Contributing to Jido Lib

Thank you for your interest in contributing to Jido Lib!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/jido_lib.git`
3. Set up the development environment: `mix setup`
4. Create a feature branch: `git checkout -b feat/your-feature`

## Development Workflow

### Running Tests

```bash
mix test
```

### Code Quality

Before committing, run:

```bash
mix quality
```

This runs:
- `mix format` - Code formatting
- `mix credo --strict` - Linting
- `mix dialyxir` - Type checking
- `mix doctor --raise` - Documentation coverage

### Documentation

Generate documentation locally:

```bash
mix docs
```

Documentation coverage is enforced via `mix doctor --raise`.

## Commit Guidelines

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

[optional body]
[optional footer]
```

**Types:**

- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Formatting, no code change
- `refactor` - Code change, no fix or feature
- `perf` - Performance improvement
- `test` - Adding/fixing tests
- `chore` - Maintenance, deps, tooling
- `ci` - CI/CD changes

**Examples:**

```bash
git commit -m "feat(agents): add new file operations agent"
git commit -m "fix: resolve timeout in async operations"
git commit -m "docs: update README with examples"
```

## Code Style

- Follow the Elixir style guide
- Use 2-space indentation
- Maximum line length: 120 characters
- Use meaningful variable and function names

## Pull Request Process

1. Ensure all tests pass: `mix test`
2. Ensure code quality: `mix quality`
3. Update documentation if needed
4. Update `CHANGELOG.md` with your changes
5. Create a descriptive pull request

## Questions?

Feel free to open an issue or reach out to the maintainers.
