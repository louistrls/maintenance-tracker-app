import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:maintenance_app/models/maintenance_task.dart';
import 'package:maintenance_app/models/equipment.dart';
import 'package:maintenance_app/services/auth_service.dart';
import 'package:maintenance_app/services/offline_manager.dart';
import 'package:maintenance_app/config/constants.dart';
import 'package:maintenance_app/widgets/parts_dropdown_card.dart'; // Nouveau import
import 'package:url_launcher/url_launcher.dart';
import 'package:maintenance_app/services/parts_api_service.dart';

import '../../widgets/parts_checklist_card.dart';

class TaskDetailScreen extends StatefulWidget {
  final MaintenanceTask task;

  const TaskDetailScreen({super.key, required this.task});

  @override
  TaskDetailScreenState createState() => TaskDetailScreenState();
}

class TaskDetailScreenState extends State<TaskDetailScreen> with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRefreshing = false;

  MaintenanceTask? _completeTask;
  Equipment? _equipment;
  int? _selectedStatus;

  // Services
  final OfflineManager _offlineManager = OfflineManager();

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  PartsApiService? _partsApiService;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.task.status;

    _fadeController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    // Charger les données
    _initializeData();
    _initializePartsApiService();
  }

  void _initializePartsApiService() {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.apiService != null) {
      _partsApiService = PartsApiService(
        baseUrl: authService.apiService!.baseUrl,
        headers: authService.apiService!.headers,
      );
    }
  }

  void _onPartsUpdated(List<Map<String, dynamic>> updatedParts) {
    setState(() {
      if (_completeTask != null) {
        _completeTask = _completeTask!.copyWithUpdatedParts(updatedParts);
      }
    });

    // Vérifier l'auto-complétion
    _checkAutoCompletion(updatedParts);
  }

  void _checkAutoCompletion(List<Map<String, dynamic>> parts) {
    if (parts.isEmpty) return;

    // Vérifier si toutes les pièces sont cochées
    bool allChecked = parts.every((part) => part['done'] == true);

    // Auto-complétion : passer en "Completed" si toutes les pièces sont cochées
    if (allChecked && _selectedStatus != AppConstants.STATUS_COMPLETED) {
      _updateTaskStatus(AppConstants.STATUS_COMPLETED);
      _showSuccessSnackBar(
          '✅ Task automatically completed - all parts checked!');
    }
    // Retour en arrière : si une pièce est décochée et que la tâche était complétée
    else if (!allChecked && _selectedStatus == AppConstants.STATUS_COMPLETED) {
      // Revenir au statut "In Progress" par défaut
      _updateTaskStatus(AppConstants.STATUS_IN_PROGRESS);
      _showInfoSnackBar(
          'Task status changed to In Progress - not all parts completed');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      await _loadCompleteTaskData();
      _startAnimations();
    } catch (e) {
      _showErrorSnackBar('Error while loading data: ${e.toString()}');
    }
  }

  /// Lance les animations d'entrée
  void _startAnimations() {
    _fadeController.forward();
    _slideController.forward();
  }

  /// Charge toutes les données de la tâche (online/offline)
  Future<void> _loadCompleteTaskData({bool forceRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      if (forceRefresh) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      final completeTask = await _offlineManager.getCompleteTask(
          authService, widget.task.id);

      if (completeTask != null && mounted) {
        setState(() {
          _completeTask = completeTask;
          _equipment = completeTask.equipment;
          _selectedStatus = completeTask.status;
        });
      } else {
        // Fallback vers les données du widget initial
        _loadFallbackData();
      }
    } catch (e) {
      print('Error while loading data: $e');
      _loadFallbackData();

      if (mounted) {
        _showErrorSnackBar(
            'Unable to retrieve all data. Cached data may be outdated.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  /// Charge les données de fallback depuis le widget
  void _loadFallbackData() {
    setState(() {
      _completeTask = widget.task;
      _equipment = widget.task.equipment;
    });
  }

  /// Met à jour le statut de la tâche
  Future<void> _updateTaskStatus(int newStatus) async {
    if (newStatus == _selectedStatus) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      if (_offlineManager.isOffline || authService.isOfflineMode) {
        // Mode hors ligne : ajouter à la queue de synchronisation
        await _offlineManager.addToSyncQueue('update_task_status', {
          'task_id': widget.task.id,
          'new_status': newStatus,
          'timestamp': DateTime.now().toIso8601String(),
        });

        setState(() {
          _selectedStatus = newStatus;
        });

        _showSuccessSnackBar('Status updated (will sync later)');
      } else {
        // Mode en ligne : mise à jour directe
        final apiService = authService.apiService;
        if (apiService == null) {
          throw Exception('API service not initialized');
        }

        final updateData = {'stage_id': newStatus};
        final response = await apiService.updateMaintenanceRequest(
            widget.task.id, updateData);

        if (response != null && response['success'] == true) {
          setState(() {
            _selectedStatus = newStatus;
          });
          _showSuccessSnackBar('Status updated successfully');

          // Recharger les données pour avoir la version la plus récente
          await _loadCompleteTaskData(forceRefresh: true);
        } else {
          final errorMessage = response?['message'] ?? 'Status update failed';
          throw Exception(errorMessage);
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error while updating: ${e.toString()}');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  /// Rafraîchit les données
  Future<void> _refreshData() async {
    if (_offlineManager.isOnline) {
      await _loadCompleteTaskData(forceRefresh: true);
    } else {
      _showInfoSnackBar('Mode hors ligne - Impossible de synchroniser');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTask = _completeTask ?? widget.task;
    final statusColor = _getStatusColor(_selectedStatus ?? currentTask.status);
    final statusIcon = _getStatusIcon(_selectedStatus ?? currentTask.status);

    return Scaffold(
      appBar: AppBar(
        title: Text('Task Details'),
        backgroundColor: statusColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Indicateur de connectivité
          Container(
            margin: EdgeInsets.only(right: 16),
            child: Icon(
              _offlineManager.isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: _offlineManager.isOnline ? Colors.white : Colors.orange
                  .shade200,
            ),
          ),
          // Bouton de rafraîchissement
          if (_offlineManager.isOnline)
            IconButton(
              icon: _isRefreshing
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : Icon(Icons.refresh),
              onPressed: _isRefreshing ? null : _refreshData,
            ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading data...'),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _refreshData,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(currentTask, statusColor, statusIcon),
                  SizedBox(height: 20),
                  _buildStatusSection(currentTask),
                  SizedBox(height: 16),
                  _buildInfoCards(currentTask),
                  SizedBox(height: 16),
                  _buildDescriptionCard(currentTask),
                  SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final screenWidth = MediaQuery
                          .of(context)
                          .size
                          .width;
                      // Seuil typique pour mobile : < 600px
                      if (screenWidth < 600) {
                        // Affichage en colonne (l'une sous l'autre)
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildEquipmentCard(),
                            SizedBox(height: 16),
                            PartsChecklistCard(
                              parts: currentTask.parts,
                              taskId: currentTask.id,
                              partsApiService: _partsApiService,
                              onPartsUpdated: _onPartsUpdated,
                            ),
                          ],
                        );
                      } else {
                        // Affichage côte à côte (desktop/tablette)
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildEquipmentCard()),
                            SizedBox(width: 16),
                            Expanded(child: PartsChecklistCard(
                              parts: currentTask.parts,
                              taskId: currentTask.id,
                              partsApiService: _partsApiService,
                              onPartsUpdated: _onPartsUpdated,
                            ),),
                          ],
                        );
                      }
                    },
                  ),
                  SizedBox(height: 16),
                  _buildActionButtons(),
                  SizedBox(height: 16),
                  _buildOfflineStatusCard(),
                  SizedBox(height: 80), // Espace pour les boutons flottants
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: null,
    );
  }

  // ... Le reste du code reste identique aux méthodes existantes ...

  /// Construction du header avec informations principales
  Widget _buildHeader(MaintenanceTask task, Color statusColor,
      IconData statusIcon) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor.withOpacity(0.8), statusColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.3),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(statusIcon, color: Colors.white, size: 32),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                            Icons.location_on, color: Colors.white70, size: 16),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            task.location,
                            style: TextStyle(color: Colors.white70,
                                fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.access_time, color: Colors.white70, size: 16),
              SizedBox(width: 4),
              Text(
                'Programmed: ${DateFormat('dd/MM/yyyy HH:mm').format(
                    task.scheduledDate)}',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Construction de la section de statut
  Widget _buildStatusSection(MaintenanceTask task) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Task Status',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 12),
            _isSaving
                ? Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Updating...'),
                ],
              ),
            )
                : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusButton(
                    AppConstants.STATUS_PENDING, 'Pending', Colors.orange),
                _buildStatusButton(
                    AppConstants.STATUS_IN_PROGRESS, 'In progress',
                    Colors.blue),
                _buildStatusButton(
                    AppConstants.STATUS_COMPLETED, 'Completed', Colors.green),
                _buildStatusButton(
                    AppConstants.STATUS_CANCELLED, 'Rebuttal', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Construction des cartes d'informations
  Widget _buildInfoCards(MaintenanceTask task) {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(
            'Priority',
            _getPriorityLabel(task.priority),
            _getPriorityIcon(task.priority),
            _getPriorityColor(task.priority),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _buildInfoCard(
            'Created on',
            DateFormat('dd/MM/yy').format(task.createdAt),
            Icons.calendar_today,
            Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon,
      Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Construction de la carte de description
  Widget _buildDescriptionCard(MaintenanceTask task) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Description',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            task.description.isEmpty
                ? Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey.shade500),
                  SizedBox(width: 8),
                  Text(
                    'No description provided',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            )
                : Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Html(
                data: task.description,
                style: {
                  "body": Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construction de la carte d'équipement
  Widget _buildEquipmentCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.engineering, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Equipment',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            _equipment == null
                ? Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Equipment information not available',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (_offlineManager.isOffline)
                          Text(
                            'Data may be outdated due to offline mode',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            )
                : Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _equipment!.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.category, size: 16,
                          color: Colors.grey.shade600),
                      SizedBox(width: 4),
                      Text(
                        'Category: ${_equipment!.category}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16,
                          color: Colors.grey.shade600),
                      SizedBox(width: 4),
                      Text(
                        'Emplacement: ${_equipment!.location}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  if (_equipment!.model3dViewerUrl != null &&
                      _equipment!.model3dViewerUrl!.isNotEmpty) ...[
                    SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _launchUrl(_equipment!.model3dViewerUrl!),
                      icon: Icon(Icons.view_in_ar, size: 18),
                      label: Text('See 3D Model'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        if (_offlineManager.isOffline)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            margin: EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offline mode enabled - All data is available locally',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Construction de la carte de statut hors ligne
  Widget _buildOfflineStatusCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _offlineManager.isOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: _offlineManager.isOnline ? Colors.green : Colors
                      .orange,
                ),
                SizedBox(width: 8),
                Text(
                  'Synchronization Status',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              _offlineManager.isOnline
                  ? 'Connected - All data is synchronized'
                  : 'Offline - Data is cached locally',
              style: TextStyle(
                color: _offlineManager.isOnline ? Colors.green.shade700 : Colors
                    .orange.shade700,
                fontSize: 14,
              ),
            ),
            if (!_offlineManager.isOnline) ...[
              SizedBox(height: 8),
              Text(
                'Modified tasks will be synchronized when you reconnect.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Construction d'un bouton de statut
  Widget _buildStatusButton(int status, String label, Color color) {
    final isSelected = _selectedStatus == status;

    return GestureDetector(
      onTap: () => _updateTaskStatus(status),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  /// Méthodes utilitaires pour les couleurs et icônes
  Color _getStatusColor(int status) {
    switch (status) {
      case AppConstants.STATUS_PENDING:
        return Colors.orange;
      case AppConstants.STATUS_IN_PROGRESS:
        return Colors.blue;
      case AppConstants.STATUS_COMPLETED:
        return Colors.green;
      case AppConstants.STATUS_CANCELLED:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(int status) {
    switch (status) {
      case AppConstants.STATUS_PENDING:
        return Icons.hourglass_empty;
      case AppConstants.STATUS_IN_PROGRESS:
        return Icons.engineering;
      case AppConstants.STATUS_COMPLETED:
        return Icons.check_circle;
      case AppConstants.STATUS_CANCELLED:
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 0:
        return Colors.green;
      case 1:
        return Colors.yellow.shade700;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getPriorityIcon(int priority) {
    switch (priority) {
      case 0:
        return Icons.keyboard_arrow_down;
      case 1:
        return Icons.remove;
      case 2:
        return Icons.keyboard_arrow_up;
      case 3:
        return Icons.priority_high;
      default:
        return Icons.help;
    }
  }

  String _getPriorityLabel(int priority) {
    switch (priority) {
      case 0:
        return 'Low';
      case 1:
        return 'Normal';
      case 2:
        return 'High';
      case 3:
        return 'Urgent';
      default:
        return 'Unknown';
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Méthode pour lancer une URL avec notre schéma personnalisé
  Future<void> _launchUrl(String url) async {
    try {
      String customUrl = url.replaceFirst('http', 'cmms');
      final uri = Uri.parse(customUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showErrorSnackBar('Unable to launch URL: $customUrl');
      }
    } catch (e) {
      _showErrorSnackBar('Error while opening the URL: ${e.toString()}');
    }
  }
}

