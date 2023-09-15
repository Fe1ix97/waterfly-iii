import 'dart:async';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'package:chopper/chopper.dart' show Response;
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;
import 'package:version/version.dart';

import 'package:waterflyiii/animations.dart';
import 'package:waterflyiii/auth.dart';
import 'package:waterflyiii/extensions.dart';
import 'package:waterflyiii/generated/swagger_fireflyiii_api/client_index.dart';
import 'package:waterflyiii/generated/swagger_fireflyiii_api/firefly_iii.swagger.dart';
import 'package:waterflyiii/generated/swagger_fireflyiii_api/firefly_iii_v2.swagger.dart'
    as api_v2;
import 'package:waterflyiii/pages/home/main_charts/category.dart';
import 'package:waterflyiii/pages/home/main_charts/lastdays.dart';
import 'package:waterflyiii/pages/home/main_charts/netearnings.dart';
import 'package:waterflyiii/pages/home/main_charts/summary.dart';
import 'package:waterflyiii/widgets/charts.dart';

class HomeMain extends StatefulWidget {
  const HomeMain({super.key});

  @override
  State<HomeMain> createState() => _HomeMainState();
}

class _HomeMainState extends State<HomeMain>
    with AutomaticKeepAliveClientMixin {
  final Logger log = Logger("Pages.Home.Main");

  final Map<DateTime, double> lastDaysExpense = <DateTime, double>{};
  final Map<DateTime, double> lastDaysIncome = <DateTime, double>{};
  final Map<DateTime, InsightTotalEntry> lastMonthsExpense =
      <DateTime, InsightTotalEntry>{};
  final Map<DateTime, InsightTotalEntry> lastMonthsIncome =
      <DateTime, InsightTotalEntry>{};
  final Map<DateTime, double> lastMonthsEarned = <DateTime, double>{};
  final Map<DateTime, double> lastMonthsSpent = <DateTime, double>{};
  List<ChartDataSet> overviewChartData = <ChartDataSet>[];
  final List<InsightGroupEntry> catChartData = <InsightGroupEntry>[];
  final Map<String, Budget> budgetInfos = <String, Budget>{};

  @override
  void dispose() {
    super.dispose();
  }

  Future<bool> _fetchLastDays() async {
    if (lastDaysExpense.isNotEmpty) {
      return true;
    }

    final FireflyIii api = context.read<FireflyService>().api;

    // Use noon due to dailylight saving time
    final DateTime now = DateTime.now()
        .toLocal()
        .setTimeOfDay(const TimeOfDay(hour: 12, minute: 0));

    lastDaysExpense.clear();
    lastDaysIncome.clear();

    // With a new API the number of API calls is reduced from 14 to 2
    if (context.read<FireflyService>().apiVersion! >= Version(2, 0, 7)) {
      final FireflyIiiV2 apiV2 = context.read<FireflyService>().apiV2;

      final List<int> accounts = <int>[];
      final Response<AccountArray> respAccounts =
          await api.v1AccountsGet(type: AccountTypeFilter.asset);
      respAccounts.body?.data.forEach(
        (AccountRead element) => accounts.add(int.parse(element.id)),
      );

      final Response<List<api_v2.ChartDataSetV2>> respBalanceData =
          await apiV2.v2ChartBalanceBalanceGet(
        start: DateFormat('yyyy-MM-dd', 'en_US')
            .format(now.copyWith(day: now.day - 6)),
        end: DateFormat('yyyy-MM-dd', 'en_US').format(now),
        accounts: accounts,
        period: api_v2.PeriodProperty.value_1d,
      );
      if (!respBalanceData.isSuccessful || respBalanceData.body == null) {
        if (context.mounted) {
          throw Exception(
            S.of(context).errorAPIInvalidResponse(
                respBalanceData.error?.toString() ?? ""),
          );
        } else {
          throw Exception(
            "[nocontext] Invalid API response: ${respBalanceData.error}",
          );
        }
      }

      for (api_v2.ChartDataSetV2 e in respBalanceData.body!) {
        final Map<String, dynamic> entries = e.entries as Map<String, dynamic>;
        entries.forEach(
          (String dateStr, dynamic valueStr) {
            final DateTime date = DateTime.parse(dateStr)
                .toLocal()
                .setTimeOfDay(const TimeOfDay(hour: 12, minute: 0));
            final double value = double.tryParse(valueStr) ?? 0;
            if (e.label == "earned") {
              lastDaysIncome[date] = (lastDaysIncome[date] ?? 0) + value;
            } else if (e.label == "spent") {
              lastDaysExpense[date] = (lastDaysExpense[date] ?? 0) + value;
            }
          },
        );
      }
    } else {
      // Old Method (before API v2.0.6 (Firefly III v6.0.20))
      final List<DateTime> lastDays = <DateTime>[];
      for (int i = 0; i < 7; i++) {
        lastDays.add(now.subtract(Duration(days: i)));
      }

      for (DateTime e in lastDays) {
        final Response<InsightTotal> respInsightExpense =
            await api.v1InsightExpenseTotalGet(
          start: DateFormat('yyyy-MM-dd', 'en_US').format(e),
          end: DateFormat('yyyy-MM-dd', 'en_US').format(e),
        );
        if (!respInsightExpense.isSuccessful ||
            respInsightExpense.body == null) {
          if (context.mounted) {
            throw Exception(
              S.of(context).errorAPIInvalidResponse(
                  respInsightExpense.error?.toString() ?? ""),
            );
          } else {
            throw Exception(
              "[nocontext] Invalid API response: ${respInsightExpense.error}",
            );
          }
        }

        lastDaysExpense[e] = (respInsightExpense.body?.isNotEmpty ?? false)
            ? respInsightExpense.body?.first.differenceFloat ?? 0
            : 0;

        final Response<InsightTotal> respInsightIncome =
            await api.v1InsightIncomeTotalGet(
          start: DateFormat('yyyy-MM-dd', 'en_US').format(e),
          end: DateFormat('yyyy-MM-dd', 'en_US').format(e),
        );
        if (!respInsightIncome.isSuccessful || respInsightIncome.body == null) {
          if (context.mounted) {
            throw Exception(
              S.of(context).errorAPIInvalidResponse(
                  respInsightIncome.error?.toString() ?? ""),
            );
          } else {
            throw Exception(
              "[nocontext] Invalid API response: ${respInsightIncome.error}",
            );
          }
        }
        lastDaysIncome[e] = (respInsightIncome.body?.isNotEmpty ?? false)
            ? respInsightIncome.body?.first.differenceFloat ?? 0
            : 0;
      }
    }

    return true;
  }

  Future<bool> _fetchOverviewChart() async {
    if (overviewChartData.isNotEmpty) {
      return true;
    }

    final FireflyIii api = context.read<FireflyService>().api;

    final DateTime now = DateTime.now().toLocal().clearTime();

    final Response<ChartLine> respChartData =
        await api.v1ChartAccountOverviewGet(
      start: DateFormat('yyyy-MM-dd', 'en_US')
          .format(now.copyWith(month: now.month - 3)),
      end: DateFormat('yyyy-MM-dd', 'en_US').format(now),
    );
    if (!respChartData.isSuccessful ||
        respChartData.body == null ||
        respChartData.body!.isEmpty) {
      if (context.mounted) {
        throw Exception(
          S
              .of(context)
              .errorAPIInvalidResponse(respChartData.error?.toString() ?? ""),
        );
      } else {
        throw Exception(
          "[nocontext] Invalid API response: ${respChartData.error}",
        );
      }
    }
    overviewChartData = respChartData.body!;

    return true;
  }

  Future<bool> _fetchLastMonths() async {
    if (lastMonthsExpense.isNotEmpty) {
      return true;
    }

    final FireflyIii api = context.read<FireflyService>().api;

    final DateTime now = DateTime.now().toLocal().clearTime();
    final List<DateTime> lastMonths = <DateTime>[];
    for (int i = 0; i < 3; i++) {
      lastMonths.add(DateTime(now.year, now.month - i, (i == 0) ? now.day : 1));
    }

    lastMonthsExpense.clear();
    lastMonthsIncome.clear();
    for (DateTime e in lastMonths) {
      late DateTime start;
      late DateTime end;
      if (e == lastMonths.first) {
        start = e.copyWith(day: 1);
        end = e;
      } else {
        start = e;
        end = e.copyWith(month: e.month + 1, day: 0);
      }
      final Response<InsightTotal> respInsightExpense =
          await api.v1InsightExpenseTotalGet(
        start: DateFormat('yyyy-MM-dd', 'en_US').format(start),
        end: DateFormat('yyyy-MM-dd', 'en_US').format(end),
      );
      if (!respInsightExpense.isSuccessful || respInsightExpense.body == null) {
        if (context.mounted) {
          throw Exception(
            S.of(context).errorAPIInvalidResponse(
                respInsightExpense.error?.toString() ?? ""),
          );
        } else {
          throw Exception(
            "[nocontext] Invalid API response: ${respInsightExpense.error}",
          );
        }
      }
      lastMonthsExpense[e] = respInsightExpense.body!.isNotEmpty
          ? respInsightExpense.body!.first
          : InsightTotalEntry(differenceFloat: 0);
      final Response<InsightTotal> respInsightIncome =
          await api.v1InsightIncomeTotalGet(
        start: DateFormat('yyyy-MM-dd', 'en_US').format(start),
        end: DateFormat('yyyy-MM-dd', 'en_US').format(end),
      );
      if (!respInsightIncome.isSuccessful || respInsightIncome.body == null) {
        if (context.mounted) {
          throw Exception(
            S.of(context).errorAPIInvalidResponse(
                respInsightIncome.error?.toString() ?? ""),
          );
        } else {
          throw Exception(
            "[nocontext] Invalid API response: ${respInsightIncome.error}",
          );
        }
      }
      lastMonthsIncome[e] = respInsightIncome.body!.isNotEmpty
          ? respInsightIncome.body!.first
          : InsightTotalEntry(differenceFloat: 0);
    }

    // If too big digits are present (>=100000), only show two columns to avoid
    // wrapping issues. See #30.
    double maxNum = 0;
    lastMonthsIncome.forEach((_, InsightTotalEntry value) {
      if ((value.differenceFloat ?? 0) > maxNum) {
        maxNum = value.differenceFloat ?? 0;
      }
    });
    lastMonthsExpense.forEach((_, InsightTotalEntry value) {
      if ((value.differenceFloat ?? 0) > maxNum) {
        maxNum = value.differenceFloat ?? 0;
      }
    });
    if (maxNum >= 100000) {
      lastMonthsIncome.remove(lastMonthsIncome.keys.first);
      lastMonthsExpense.remove(lastMonthsExpense.keys.first);
    }

    return true;
  }

  Future<bool> _fetchCategories() async {
    if (catChartData.isNotEmpty) {
      return true;
    }

    final FireflyIii api = context.read<FireflyService>().api;

    final DateTime now = DateTime.now().toLocal().clearTime();

    catChartData.clear();

    final Response<InsightGroup> respCatIncomeData =
        await api.v1InsightIncomeCategoryGet(
      start: DateFormat('yyyy-MM-dd', 'en_US').format(now.copyWith(day: 1)),
      end: DateFormat('yyyy-MM-dd', 'en_US').format(now),
    );
    final Response<InsightGroup> respCatExpenseData =
        await api.v1InsightExpenseCategoryGet(
      start: DateFormat('yyyy-MM-dd', 'en_US').format(now.copyWith(day: 1)),
      end: DateFormat('yyyy-MM-dd', 'en_US').format(now),
    );

    if (!respCatExpenseData.isSuccessful || respCatExpenseData.body == null) {
      if (context.mounted) {
        throw Exception(
          S.of(context).errorAPIInvalidResponse(
              respCatExpenseData.error?.toString() ?? ""),
        );
      } else {
        throw Exception(
          "[nocontext] Invalid API response: ${respCatExpenseData.error}",
        );
      }
    }

    Map<String, double> catIncomes = <String, double>{};
    for (InsightGroupEntry cat
        in respCatIncomeData.body ?? <InsightGroupEntry>[]) {
      if (cat.id?.isEmpty ?? true) {
        continue;
      }
      catIncomes[cat.id!] = cat.differenceFloat ?? 0;
    }

    for (InsightGroupEntry cat in respCatExpenseData.body!) {
      if (cat.id?.isEmpty ?? true) {
        continue;
      }
      double amount = cat.differenceFloat ?? 0;
      if (catIncomes.containsKey(cat.id)) {
        amount += catIncomes[cat.id]!;
      }
      // Don't add "positive" categories, we want to show expenses
      if (amount >= 0) {
        continue;
      }
      catChartData.add(cat.copyWith(differenceFloat: amount));
    }

    return true;
  }

  Future<List<BudgetLimitRead>> _fetchBudgets() async {
    final FireflyIii api = context.read<FireflyService>().api;

    final Response<BudgetArray> respBudgetInfos = await api.v1BudgetsGet();
    if (!respBudgetInfos.isSuccessful || respBudgetInfos.body == null) {
      if (context.mounted) {
        throw Exception(
          S
              .of(context)
              .errorAPIInvalidResponse(respBudgetInfos.error?.toString() ?? ""),
        );
      } else {
        throw Exception(
          "[nocontext] Invalid API response: ${respBudgetInfos.error}",
        );
      }
    }

    for (BudgetRead budget in respBudgetInfos.body!.data) {
      budgetInfos[budget.id] = budget.attributes;
    }

    final DateTime now = DateTime.now().toLocal().clearTime();
    final Response<BudgetLimitArray> respBudgets = await api.v1BudgetLimitsGet(
      start: DateFormat('yyyy-MM-dd', 'en_US').format(now.copyWith(day: 1)),
      end: DateFormat('yyyy-MM-dd', 'en_US').format(now),
    );

    if (!respBudgets.isSuccessful || respBudgets.body == null) {
      if (context.mounted) {
        throw Exception(
          S
              .of(context)
              .errorAPIInvalidResponse(respBudgets.error?.toString() ?? ""),
        );
      } else {
        throw Exception(
          "[nocontext] Invalid API response: ${respBudgets.error}",
        );
      }
    }

    respBudgets.body!.data.sort((BudgetLimitRead a, BudgetLimitRead b) {
      Budget? budgetA = budgetInfos[a.attributes.budgetId];
      Budget? budgetB = budgetInfos[b.attributes.budgetId];

      if (budgetA == null && budgetB != null) {
        return -1;
      } else if (budgetA != null && budgetB == null) {
        return 1;
      } else if (budgetA == null && budgetB == null) {
        return 0;
      }
      int compare = (budgetA!.order ?? -1).compareTo(budgetB!.order ?? -1);
      if (compare != 0) {
        return compare;
      }
      return a.attributes.start.compareTo(b.attributes.start);
    });

    return respBudgets.body!.data;
  }

  /*Future<bool> _fetchBalance() async {
    final FireflyIiiV2 apiV2 = context.read<FireflyService>().apiV2;

    final DateTime now = DateTime.now().toLocal().clearTime();

    lastMonthsEarned.clear();
    lastMonthsSpent.clear();

    final Response<List<api_v2.ChartDataSetV2>> respBalanceData =
        await apiV2.v2ChartBalanceBalanceGet(
      start: DateFormat('yyyy-MM-dd', 'en_US')
          //.format(now.copyWith(year: now.year - 1)),
          .format(now.copyWith(day: now.day - 7)),
      end: DateFormat('yyyy-MM-dd', 'en_US').format(now),
      accounts: <int>[1, 3],
      period: api_v2.PeriodProperty.value_1d,
    );
    if (!respBalanceData.isSuccessful || respBalanceData.body == null) {
      if (context.mounted) {
        throw Exception(
          S
              .of(context)
              .errorAPIInvalidResponse(respBalanceData.error?.toString() ?? ""),
        );
      } else {
        throw Exception(
          "[nocontext] Invalid API response: ${respBalanceData.error}",
        );
      }
    }

    for (api_v2.ChartDataSetV2 e in respBalanceData.body!) {
      final Map<String, dynamic> entries = e.entries as Map<String, dynamic>;
      entries.forEach(
        (String dateStr, dynamic valueStr) {
          final DateTime date = DateTime.parse(dateStr).toLocal();
          final double value = double.tryParse(valueStr) ?? 0;
          debugPrint("[${e.label}] $date: $value");
          if (e.label == "earned") {
            lastMonthsEarned[date] = (lastMonthsEarned[date] ?? 0) + value;
          } else if (e.label == "spent") {
            lastMonthsSpent[date] = (lastMonthsSpent[date] ?? 0) + value;
          }
        },
      );
    }

    return true;
  }*/

  Future<void> _refreshStats() async {
    setState(() {});
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    log.finest(() => "build()");

    CurrencyRead defaultCurrency =
        context.read<FireflyService>().defaultCurrency;

    return RefreshIndicator(
      onRefresh: _refreshStats,
      child: ListView(
        cacheExtent: 1000,
        padding: const EdgeInsets.all(8),
        children: <Widget>[
          ChartCard(
            title: S.of(context).homeMainChartDailyTitle,
            future: _fetchLastDays(),
            summary: () {
              double sevenDayTotal = 0;
              lastDaysExpense
                  .forEach((DateTime _, double e) => sevenDayTotal -= e.abs());
              lastDaysIncome
                  .forEach((DateTime _, double e) => sevenDayTotal += e.abs());
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(S.of(context).homeMainChartDailyAvg),
                  Text(
                    defaultCurrency.fmt(sevenDayTotal / 7),
                    style: TextStyle(
                      color: sevenDayTotal < 0 ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures()
                      ],
                    ),
                  ),
                ],
              );
            },
            height: 125,
            child: () => LastDaysChart(
              expenses: lastDaysExpense,
              incomes: lastDaysIncome,
            ),
          ),
          const SizedBox(height: 8),
          ChartCard(
            title: S.of(context).homeMainChartCategoriesTitle,
            future: _fetchCategories(),
            height: 175,
            child: () => CategoryChart(
              data: catChartData,
            ),
          ),
          const SizedBox(height: 8),
          ChartCard(
            title: S.of(context).homeMainChartAccountsTitle,
            future: _fetchOverviewChart(),
            summary: () => Table(
              //border: TableBorder.all(), // :DEBUG:
              columnWidths: const <int, TableColumnWidth>{
                0: FixedColumnWidth(24),
                1: FlexColumnWidth(),
                2: IntrinsicColumnWidth(),
              },
              children: <TableRow>[
                TableRow(
                  children: <Widget>[
                    const SizedBox.shrink(),
                    Text(
                      S.of(context).generalAccount,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        S.of(context).generalBalance,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                ...overviewChartData.mapIndexed((int i, ChartDataSet e) {
                  final Map<String, dynamic> entries =
                      e.entries! as Map<String, dynamic>;
                  final double balance =
                      double.tryParse(entries.entries.last.value) ?? 0;
                  final CurrencyRead currency = CurrencyRead(
                    id: e.currencyId ?? "0",
                    type: "currencies",
                    attributes: Currency(
                      code: e.currencyCode ?? "",
                      name: "",
                      symbol: e.currencySymbol ?? "",
                      decimalPlaces: e.currencyDecimalPlaces,
                    ),
                  );
                  return TableRow(
                    children: <Widget>[
                      Align(
                        alignment: Alignment.center,
                        child: Text(
                          "⬤",
                          style: TextStyle(
                            color: charts.ColorUtil.toDartColor(
                              possibleChartColors[
                                  i % possibleChartColors.length],
                            ),
                            textBaseline: TextBaseline.ideographic,
                            height: 1.3,
                          ),
                        ),
                      ),
                      Text(e.label!),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          currency.fmt(balance),
                          style: TextStyle(
                            color: (balance < 0) ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            height: 175,
            onTap: () => showDialog<void>(
              context: context,
              builder: (BuildContext context) => const SummaryChartPopup(),
            ),
            child: () => SummaryChart(
              data: overviewChartData,
            ),
          ),
          const SizedBox(height: 8),
          ChartCard(
            title: S.of(context).homeMainChartNetearningsTitle,
            future: _fetchLastMonths(),
            summary: () => Table(
              // border: TableBorder.all(), // :DEBUG:
              columnWidths: const <int, TableColumnWidth>{
                0: FixedColumnWidth(24),
                1: IntrinsicColumnWidth(),
                2: FlexColumnWidth(),
                3: FlexColumnWidth(),
                4: FlexColumnWidth(),
              },
              children: <TableRow>[
                TableRow(
                  children: <Widget>[
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    ...lastMonthsIncome.keys.toList().reversed.map(
                          (DateTime e) => Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              DateFormat(DateFormat.MONTH).format(e),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ),
                  ],
                ),
                TableRow(
                  children: <Widget>[
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        "⬤",
                        style: TextStyle(
                          color: Colors.green,
                          textBaseline: TextBaseline.ideographic,
                          height: 1.3,
                        ),
                      ),
                    ),
                    Text(S.of(context).generalIncome),
                    ...lastMonthsIncome.entries.toList().reversed.map(
                          (MapEntry<DateTime, InsightTotalEntry> e) => Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              defaultCurrency.fmt(e.value.differenceFloat ?? 0),
                              style: const TextStyle(
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
                TableRow(
                  children: <Widget>[
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        "⬤",
                        style: TextStyle(
                          color: Colors.red,
                          textBaseline: TextBaseline.ideographic,
                          height: 1.3,
                        ),
                      ),
                    ),
                    Text(S.of(context).generalExpenses),
                    ...lastMonthsExpense.entries.toList().reversed.map(
                          (MapEntry<DateTime, InsightTotalEntry> e) => Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              defaultCurrency.fmt(e.value.differenceFloat ?? 0),
                              style: const TextStyle(
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
                TableRow(
                  children: <Widget>[
                    const SizedBox.shrink(),
                    Text(
                      S.of(context).generalSum,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...lastMonthsIncome.entries.toList().reversed.map(
                      (MapEntry<DateTime, InsightTotalEntry> e) {
                        final double income = e.value.differenceFloat ?? 0;
                        double expense = 0;
                        if (lastMonthsExpense.containsKey(e.key)) {
                          expense =
                              lastMonthsExpense[e.key]!.differenceFloat ?? 0;
                        }
                        double sum = income + expense;
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            defaultCurrency.fmt(sum),
                            style: TextStyle(
                              color: (sum < 0) ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            child: () => NetEarningsChart(
              expenses: lastMonthsExpense,
              income: lastMonthsIncome,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedHeight(
            child: Card(
              clipBehavior: Clip.hardEdge,
              child: FutureBuilder<List<BudgetLimitRead>>(
                future: _fetchBudgets(),
                builder: (BuildContext context,
                    AsyncSnapshot<List<BudgetLimitRead>> snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            S.of(context).homeMainBudgetTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        BudgetList(
                          budgetInfos: budgetInfos,
                          snapshot: snapshot,
                        ),
                      ],
                    );
                  } else if (snapshot.hasError) {
                    return Text(snapshot.error!.toString());
                  } else {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 68),
        ],
      ),
    );
  }
}

class BudgetList extends StatelessWidget {
  const BudgetList({
    super.key,
    required this.budgetInfos,
    required this.snapshot,
  });

  final Map<String, Budget> budgetInfos;
  final AsyncSnapshot<List<BudgetLimitRead>> snapshot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final List<Widget> widgets = <Widget>[];
            for (BudgetLimitRead budget in snapshot.data!) {
              final double spent =
                  (double.tryParse(budget.attributes.spent ?? "0") ?? 0).abs();
              final double available =
                  double.tryParse(budget.attributes.amount) ?? 0;
              Budget? budgetInfo = budgetInfos[budget.attributes.budgetId];
              if (budgetInfo == null || available == 0) {
                continue;
              }
              final CurrencyRead currency = CurrencyRead(
                id: budget.attributes.currencyId ?? "0",
                type: "currencies",
                attributes: Currency(
                  code: budget.attributes.currencyCode ?? "",
                  name: budget.attributes.currencyName ?? "",
                  symbol: budget.attributes.currencySymbol ?? "",
                  decimalPlaces: budget.attributes.currencyDecimalPlaces,
                ),
              );
              Color lineColor = Colors.green;
              Color? bgColor;
              double value = spent / available;
              if (spent > available) {
                lineColor = Colors.red;
                bgColor = Colors.green;
                value = value % 1;
              }

              if (widgets.isNotEmpty) {
                widgets.add(const SizedBox(height: 8));
              }
              widgets.add(
                RichText(
                  text: TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: budgetInfo.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      TextSpan(
                        text: S.of(context).homeMainBudgetInterval(
                              budget.attributes.start.toLocal(),
                              budget.attributes.end.toLocal(),
                              budget.attributes.period ?? "",
                            ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              );
              widgets.add(Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    S.of(context).numPercent(spent / available),
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge!
                        .copyWith(color: lineColor),
                  ),
                  Text(
                    S.of(context).homeMainBudgetSum(
                          currency.fmt(
                            (available - spent).abs(),
                            decimalDigits: 0,
                          ),
                          (spent > available) ? "over" : "leftfrom",
                          currency.fmt(
                            available,
                            decimalDigits: 0,
                          ),
                        ),
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge!
                        .copyWith(color: lineColor),
                  ),
                ],
              ));
              widgets.add(LinearProgressIndicator(
                color: lineColor,
                backgroundColor: bgColor,
                value: value,
              ));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widgets,
            );
          },
        ),
      ),
    );
  }
}

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    required this.future,
    this.height = 150,
    this.summary,
    this.onTap,
  });

  final String title;
  final Widget Function() child;
  final Future<bool> future;
  final Widget Function()? summary;
  final double height;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    List<Widget> summaryWidgets = <Widget>[];

    return AnimatedHeight(
      child: Card(
        clipBehavior: Clip.hardEdge,
        child: FutureBuilder<bool>(
          future: future,
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData) {
              if (summary != null) {
                summaryWidgets.add(const Divider(indent: 16, endIndent: 16));
                summaryWidgets.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: summary!(),
                  ),
                );
              }
              return InkWell(
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          onTap != null
                              ? Icon(
                                  Icons.touch_app_outlined,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                )
                              : const SizedBox.shrink(),
                        ],
                      ),
                    ),
                    Ink(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                      ),
                      child: SizedBox(
                        height: height,
                        child: child(),
                      ),
                    ),
                    ...summaryWidgets,
                  ],
                ),
              );
            } else if (snapshot.hasError) {
              log.severe("Error getting chart card data", snapshot.error,
                  snapshot.stackTrace);
              return Text(snapshot.error!.toString());
            } else {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
