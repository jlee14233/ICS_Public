import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:intl/intl.dart';

import '../../providers/glider_provider.dart';
import '../../providers/archive_glider_provider.dart';
import 'archive_detail_screen.dart';

/// 아카이브 관리 허브 화면.
/// 네비게이션 흐름: [Live Dashboard] → [ArchiveHubScreen] → [ArchiveDetailScreen]
///
/// 상단: 운용 중인 글라이더 버튼 (Archive Trigger)
/// 하단: 미션 히스토리 데이터베이스 (Placeholder)
class ArchiveHubScreen extends StatelessWidget {
  const ArchiveHubScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ArchiveGliderProvider(),
      child: const _ArchiveHubContent(),
    );
  }
}

class _ArchiveHubContent extends StatefulWidget {
  const _ArchiveHubContent({Key? key}) : super(key: key);

  @override
  State<_ArchiveHubContent> createState() => _ArchiveHubContentState();
}

class _ArchiveHubContentState extends State<_ArchiveHubContent> {
  // ================================================================
  // 아카이빙 확인 다이얼로그
  // ================================================================

  /// "yes" 입력 기반의 안전 아카이빙 확인 다이얼로그를 표시한다.
  Future<void> _showArchiveDialog(
    BuildContext context,
    String gliderName,
  ) async {
    final textController = TextEditingController();
    bool isConfirmEnabled = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('미션 아카이브 처리'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '정말로 현재 운용 중인 $gliderName 미션을 아카이빙 할건가요?\n'
                    '진행하려면 "yes"를 입력하세요.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'yes',
                      border: const OutlineInputBorder(),
                      suffixIcon: isConfirmEnabled
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.cancel, color: Colors.grey),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        isConfirmEnabled = value.trim().toLowerCase() == 'yes';
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: isConfirmEnabled
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: const Text('확인 (아카이브 실행)'),
                ),
              ],
            );
          },
        );
      },
    );

    textController.dispose();

    if (confirmed == true && mounted) {
      final gliderProvider = context.read<GliderProvider>();
      final success = await gliderProvider.archiveCurrentMission(gliderName);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$gliderName 아카이브 이관이 요청되었습니다.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        context.read<ArchiveGliderProvider>().scanAllMissions();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gliderProvider = context.watch<GliderProvider>();
    final archiveProvider = context.watch<ArchiveGliderProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archive Management Hub'),
        backgroundColor: Colors.blueGrey[800],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ================================================================
            // 상단 섹션: Active Glider Management
            // ================================================================
            Container(
              margin: const EdgeInsets.all(12.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.blueGrey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.flight_takeoff,
                        color: Colors.blueGrey[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '운용 중인 글라이더',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${gliderProvider.activeGliders.length}대 운용',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  gliderProvider.activeGliders.isEmpty
                      ? const Text(
                          '현재 운용 중인 글라이더가 없습니다.',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        )
                      : Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: gliderProvider.activeGliders.map((glider) {
                            return ActionChip(
                              avatar: const Icon(
                                Icons.archive_outlined,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: Text(
                                glider,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              backgroundColor: Colors.blueGrey[600],
                              side: BorderSide.none,
                              onPressed: () =>
                                  _showArchiveDialog(context, glider),
                            );
                          }).toList(),
                        ),
                ],
              ),
            ),

            // ================================================================
            // 구분선
            // ================================================================
            const Divider(height: 1, thickness: 1, indent: 12, endIndent: 12),

            // ================================================================
            // 하단 섹션: Mission Archive Database (Placeholder)
            // ================================================================
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Row(
                children: [
                  Icon(Icons.storage, color: Colors.blueGrey[700], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '미션 아카이브 데이터베이스',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: archiveProvider.isLoadingAllMissions
                    ? const Center(child: CircularProgressIndicator())
                    : archiveProvider.allArchivedMissions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '아카이브된 미션이 없습니다.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DataTable2(
                          columnSpacing: 16,
                          horizontalMargin: 16,
                          minWidth: 700,
                          headingRowColor: WidgetStateProperty.all(
                            Colors.blueGrey[50],
                          ),
                          headingTextStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey[800],
                            fontSize: 13,
                          ),
                          dataTextStyle: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                          columns: const [
                            DataColumn2(
                              label: Text('미션 이름'),
                              size: ColumnSize.L,
                            ),
                            DataColumn2(
                              label: Text('운용 시작일'),
                              size: ColumnSize.M,
                            ),
                            DataColumn2(
                              label: Text('운용 종료일'),
                              size: ColumnSize.M,
                            ),
                            DataColumn2(
                              label: Text('보관 날짜'),
                              size: ColumnSize.M,
                            ),
                          ],
                          rows: archiveProvider.allArchivedMissions.map((
                            mission,
                          ) {
                            final dateFormat = DateFormat('yyyy년 MM월 dd일');
                            return DataRow2(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ArchiveDetailScreen(
                                      gliderName: mission.gliderName,
                                      initialFolderName: mission.folderName,
                                    ),
                                  ),
                                );
                              },
                              cells: [
                                DataCell(
                                  Text(
                                    mission.folderName,
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    mission.startDate != null
                                        ? dateFormat.format(mission.startDate!)
                                        : '-',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    mission.endDate != null
                                        ? dateFormat.format(mission.endDate!)
                                        : '-',
                                  ),
                                ),
                                DataCell(
                                  Text(dateFormat.format(mission.archivedDate)),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
