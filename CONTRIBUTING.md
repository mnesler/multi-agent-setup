# Contributing to Multi-Agent System

Thank you for your interest in contributing to the Multi-Agent System project!

## How to Contribute

### Reporting Issues

If you find a bug or have a suggestion:

1. Check if the issue already exists in the GitHub Issues
2. If not, create a new issue with:
   - Clear description of the problem/suggestion
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - System information (OS, tmux version, SQLite version)
   - Relevant logs or error messages

### Submitting Changes

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow the existing code style
   - Add comments for complex logic
   - Update documentation if needed

4. **Test your changes**
   ```bash
   ./verify-setup.sh
   ```

5. **Commit your changes**
   ```bash
   git add .
   git commit -m "Add: brief description of changes"
   ```

6. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Create a Pull Request**
   - Describe your changes
   - Reference any related issues
   - Explain why the change is needed

## Development Guidelines

### Code Style

- **Shell scripts**: Follow existing style, use `set -e` for safety
- **Functions**: Add comments describing purpose and parameters
- **Error handling**: Always check return codes for critical operations
- **Logging**: Use consistent log levels (INFO, WARN, ERROR)

### Testing

Before submitting:
- Run `./verify-setup.sh` to ensure basic functionality
- Test with different agent configurations
- Verify database operations work correctly
- Check that tmux session creation works

### Documentation

- Update README.md for user-facing changes
- Update EXAMPLES.md for new workflow patterns
- Add comments in code for complex logic
- Update PROJECT_SUMMARY.md for architectural changes

## Areas for Contribution

### High Priority
- Web-based monitoring dashboard
- Additional task types
- Better error handling and recovery
- Performance optimizations
- Test suite

### Medium Priority
- MCP server integration
- Task dependencies (DAG execution)
- Remote agent support
- Additional agent types
- Metrics and analytics

### Low Priority
- Additional examples and workflows
- Documentation improvements
- Code refactoring
- UI/UX improvements

## Questions?

Feel free to open an issue for discussion before starting work on major changes.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
