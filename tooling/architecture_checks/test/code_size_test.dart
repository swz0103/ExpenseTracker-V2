import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The app's code, measured.
const app = 'apps/expense_tracker/lib';

/// The most lines a function, method or constructor may take, from its
/// first word to its closing brace, its doc comment left out (Martin,
/// *Clean Code*, ch. 3: a function does one thing; past a screen it no
/// longer reads as one).
const functionLimit = 80;

/// The most lines a library may take with all its parts: a part is
/// another file of the same library, so splitting into parts does not
/// make a library smaller.
const libraryLimit = 1200;

/// What is over a limit today, at its size today. Each may only shrink:
/// one that grows fails, and one that shrank a good deal must have its
/// number lowered here, so the list only ever gets shorter.
const longerFunctions = <String, int>{
  // Drawn by tool/glyphs.py from the icon paths, one case per glyph.
  'src/core/look/glyphs.dart::_draw': 1541,
  'src/app/demo/seed.dart::demoLedger': 448,
  'src/features/entries/compose/composer_state.dart::_ComposerState.build': 212,
  'src/features/accounts/ui/sort_accounts.dart::_SortAccountsPageState.build':
      203,
  'src/features/investments/ui/investments.dart::_InvestmentsPageState.build':
      199,
  'src/features/investments/ui/holding_bento.dart::_PriceChartState.build': 191,
  'src/features/investments/ui/investments_returns.dart::_ReturnsState.build':
      184,
  'src/features/tags/ui/tags_page.dart::ProjectCard.build': 164,
  'src/features/accounts/compose/account_editor_state.dart::_AccountEditorState.build':
      121,
  'src/features/recurring/ui/recurring_calendar.dart::_Calendar._dayCell': 157,
  'src/app/demo/seed_history.dart::_history': 152,
  'src/features/recurring/ui/recurring_page.dart::_RecurringPageState.build':
      150,
  'src/features/entries/compose/composer_view.dart::_View._view': 144,
  'src/core/ledger/portfolio.dart::Portfolio.replay': 143,
  'src/features/entries/ui/entries_page.dart::_EntriesPageState._head': 138,
  'src/features/reports/ui/report_blocks.dart::_Hero.build': 138,
  'src/features/settings/ui/update_panel.dart::_UpdatePanelState.build': 137,
  'src/features/reports/ui/reports_page_state.dart::_ReportsPageState.build':
      133,
  'src/features/recurring/compose/recurring_repeat.dart::_RepeatSheetState.build':
      133,
  'src/core/charts/flow_chart.dart::_FlowPainter.paint': 131,
  'src/features/accounts/ui/account_page.dart::_AccountBodyState.build': 124,
  'src/core/ui/balance_hero.dart::BalanceHero.build': 123,
  'src/features/lock/ui/views/welcome_view.dart::_WelcomeViewState._foundChoices':
      123,
  'src/features/reports/ui/compare_section.dart::_CompareSectionState.build':
      122,
  'src/features/budgets/ui/budgets.dart::_BudgetsPageState.build': 122,
  'src/features/investments/ui/holding_page.dart::HoldingPage.build': 122,
  'src/features/recurring/ui/recurring_calendar.dart::_DayItemsState._itemCard':
      121,
  'src/features/investments/ui/investments_hero.dart::_InvestHero.build': 120,
  'src/features/accounts/ui/account_card.dart::AccountCard.build': 115,
  'src/features/lock/ui/views/unlock_view.dart::_UnlockViewState._page': 114,
  'src/app/settings_page.dart::SettingsPage._index': 114,
  'src/features/overview/ui/sections/daily_section.dart::_DailySectionState._daily':
      113,
  'src/features/categories/ui/categories_page.dart::_CategoriesPageState.build':
      113,
  'src/features/budgets/ui/budgets_month_picker.dart::_MonthPickerState.build':
      113,
  'src/core/ui/calculator.dart::_CalculatorState.build': 113,
  'src/core/ui/tour.dart::_Card.build': 112,
  'src/features/entries/compose/composer_extras.dart::_Extras._receiptSquare':
      111,
  'src/features/reports/ui/reports_page_state.dart::_ReportsPageState._flow':
      108,
  'src/features/investments/ui/holding_bento.dart::_LinePainter.paint': 108,
  'src/features/budgets/ui/budgets.dart::_Main.build': 108,
  'src/features/accounts/compose/loan_fields.dart::_Estimate.build': 106,
  'src/features/settings/ui/preferences_section.dart::_LookChoice.build': 106,
  'src/app/shell.dart::_BottomBar.build': 105,
  'src/features/import_export/ui/import_export_section.dart::_ExportSheetState.build':
      105,
  'src/app/more_page.dart::MorePage.build': 104,
  'src/features/accounts/compose/loan_fields.dart::extension._loanFields': 102,
  'src/features/overview/compose/widget_face.dart::WidgetFace.build': 101,
  'src/features/accounts/compose/account_editor_edit_card.dart::_EditCard.build':
      100,
  'src/features/budgets/ui/budgets_pace.dart::_Limit.build': 100,
  'src/features/overview/ui/sections/assets_section.dart::_AssetsSectionState._assets':
      98,
  'src/core/look/time_panels.dart::_RangePanelState.build': 97,
  'src/features/debts/ui/person_page.dart::LoanPage.build': 97,
  'src/features/reports/ui/reports_habits.dart::_Habits._merchants': 96,
  'src/features/debts/ui/person_page.dart::PersonPage.build': 95,
  'src/app/shell.dart::_AppShellState._body': 95,
  'src/features/accounts/compose/loan_fields.dart::_LoanCard.build': 94,
  'src/core/ui/entry_tile.dart::EntryTile.build': 93,
  'src/features/investments/ui/holding_page.dart::_DividendCard.build': 93,
  'src/core/ledger/persistence/sql_ledger_data_source.dart::SqlLedgerDataSource.refreshQuotes':
      93,
  'src/features/entries/compose/composer_investment.dart::_HoldingChoicesState.build':
      92,
  'src/features/entries/compose/composer_investment.dart::_InvestmentFields._tradeFold':
      92,
  'src/app/demo/launch.dart::_HomeScreen._wallpaper': 92,
  'src/features/budgets/ui/budgets_month_picker.dart::_AddLimit.build': 91,
  'src/features/recurring/ui/recurring_lists.dart::_Subscriptions.build': 91,
  'src/features/entries/compose/composer_usual_chip.dart::_OwedCard.build': 89,
  'src/core/charts/waterfall.dart::_WaterfallPainter.paint': 89,
  'src/core/look/time_panels.dart::_TimePanelState.build': 88,
  'src/features/reports/ui/report_figures.dart::_Report.of': 87,
  'src/features/reports/ui/reports_habits.dart::_Habits._weekdays': 86,
  'src/features/recurring/ui/recurring_rows.dart::_ItemRow.build': 86,
  'src/features/accounts/ui/accounts.dart::_NetWorth.build': 86,
  'src/features/entries/compose/composer_investment.dart::_InvestmentFields._dividendFold':
      84,
  'src/features/overview/ui/sections/plan_section.dart::PlanSection._budgetTile':
      84,
  'src/features/entries/ui/entries_filter_sheet.dart::_FilterSheetState.build':
      84,
  'src/features/reports/ui/reports_page_state.dart::_ReportsPageState._mix': 84,
  'src/core/ledger/persistence/sql_ledger_data_source.dart::SqlLedgerDataSource._load':
      84,
  'src/features/tags/ui/tags_page.dart::_TagsPageState._merchantList': 84,
  'src/features/overview/model/home_widget.dart::widgetSnapshot': 82,
  'src/features/reminders/ui/reminders_section.dart::_RemindersSectionState._calendarDetails':
      82,
  'src/features/recurring/compose/recurring_repeat.dart::_OtherSheetState.build':
      81,
  'src/features/debts/ui/debts_page.dart::_DebtHero.build': 81,
  'src/core/look/dialogs.dart::confirm': 81,
};
const largerLibraries = <String, int>{
  'src/features/entries/compose/composer.dart': 4540,
  'src/core/look/glyphs.dart': 1942,
  'src/features/accounts/compose/account_editor.dart': 1462,
  'src/features/reports/ui/reports.dart': 1524,
};

/// How far below its number an entry may fall before the number must be
/// lowered to it.
const slack = 20;

/// [relative] with `/` between its folders on every system, as the
/// lists above are written.
String _key(String relative) => p.posix.joinAll(p.split(relative));

final root = p.normalize(p.join(Directory.current.path, '..', '..'));

/// One function's name and length.
typedef Measure = ({String name, int lines});

final class _Functions extends RecursiveAstVisitor<void> {
  _Functions(this.lineInfo, this.file);

  final LineInfo lineInfo;
  final String file;
  final found = <Measure>[];
  final _owners = <String>[];

  int _lines(AstNode node, Token first) =>
      lineInfo.getLocation(node.end).lineNumber -
      lineInfo.getLocation(first.offset).lineNumber +
      1;

  void _add(String name, AstNode node, Token first) {
    final owner = _owners.isEmpty ? '' : '${_owners.last}.';
    found.add((name: '$file::$owner$name', lines: _lines(node, first)));
  }

  void _inside(String owner, void Function() visit) {
    _owners.add(owner);
    visit();
    _owners.removeLast();
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) => _inside(
    node.namePart.typeName.lexeme,
    () => super.visitClassDeclaration(node),
  );

  @override
  void visitMixinDeclaration(MixinDeclaration node) =>
      _inside(node.name.lexeme, () => super.visitMixinDeclaration(node));

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) => _inside(
    node.name?.lexeme ?? 'extension',
    () => super.visitExtensionDeclaration(node),
  );

  @override
  void visitEnumDeclaration(EnumDeclaration node) => _inside(
    node.namePart.typeName.lexeme,
    () => super.visitEnumDeclaration(node),
  );

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _add(node.name.lexeme, node, node.firstTokenAfterCommentAndMetadata);
    _inside(node.name.lexeme, () => super.visitFunctionDeclaration(node));
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _add(node.name.lexeme, node, node.firstTokenAfterCommentAndMetadata);
    _inside(node.name.lexeme, () => super.visitMethodDeclaration(node));
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _add(
      node.name?.lexeme ?? 'new',
      node,
      node.firstTokenAfterCommentAndMetadata,
    );
    super.visitConstructorDeclaration(node);
  }
}

void main() {
  final files = [
    for (final f in Directory(p.join(root, app)).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ]..sort((a, b) => a.path.compareTo(b.path));
  final units = {
    for (final f in files)
      _key(p.relative(f.path, from: p.join(root, app))): parseString(
        content: f.readAsStringSync(),
        path: f.path,
        throwIfDiagnostics: false,
      ),
  };

  test('no function is longer than $functionLimit lines', () {
    final over = <String, int>{};
    for (final MapEntry(key: file, value: result) in units.entries) {
      final visitor = _Functions(result.lineInfo, file);
      result.unit.accept(visitor);
      for (final m in visitor.found) {
        if (m.lines > functionLimit) over[m.name] = m.lines;
      }
    }
    _ratchet(over, longerFunctions, 'function');
  });

  test('no library is longer than $libraryLimit lines with its parts', () {
    final over = <String, int>{};
    for (final MapEntry(key: file, value: result) in units.entries) {
      final unit = result.unit;
      if (unit.directives.any((d) => d is PartOfDirective)) continue;
      var lines = result.lineInfo.lineCount;
      for (final part in unit.directives.whereType<PartDirective>()) {
        final uri = part.uri.stringValue;
        final kept = uri == null
            ? null
            : units[p.posix.normalize(
                p.posix.join(p.posix.dirname(file), uri),
              )];
        if (kept == null) fail('$file: its part ${part.uri} is not found');
        lines += kept.lineInfo.lineCount;
      }
      if (lines > libraryLimit) over[file] = lines;
    }
    _ratchet(over, largerLibraries, 'library');
  });
}

/// Fails on anything over the limit that is not in [known], larger than
/// [known] says, or so much smaller that [known] should be lowered.
void _ratchet(Map<String, int> over, Map<String, int> known, String what) {
  final problems = <String>[
    for (final MapEntry(:key, :value) in over.entries)
      if (known[key] case final allowed?)
        if (value > allowed)
          '$key grew to $value lines (allowed $allowed)'
        else if (value < allowed - slack)
          '$key is down to $value lines: lower its number from $allowed'
        else
          ''
      else
        '$key has $value lines: split the $what',
    for (final key in known.keys)
      if (!over.containsKey(key))
        '$key is within the limit: take it off the list',
  ]..removeWhere((problem) => problem.isEmpty);
  if (Platform.environment['PRINT_SIZES'] != null) {
    for (final e
        in (over.entries.toList()..sort((a, b) => b.value - a.value))) {
      print("    '${e.key}': ${e.value},");
    }
  }
  expect(problems, isEmpty, reason: problems.join('\n'));
}
