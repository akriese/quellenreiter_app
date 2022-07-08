import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:quellenreiter_app/models/quellenreiter_app_state.dart';
import '../../widgets/statement_card.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({Key? key, required this.appState}) : super(key: key);

  final QuellenreiterAppState appState;
  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  @override
  Widget build(BuildContext context) {
    if (widget.appState.safedStatements == null) {
      return const Center(
        child: Text("Keine gespeicherten Fakten oder Fakes."),
      );
    }

    return AnimationLimiter(
      child: ListView.builder(
        itemCount: widget.appState.safedStatements!.statements.length,
        itemBuilder: (BuildContext context, int index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              horizontalOffset: 20.0,
              curve: Curves.elasticOut,
              child: FadeInAnimation(
                child: StatementCard(
                  statement: widget.appState.safedStatements!.statements[index],
                  appState: widget.appState,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
