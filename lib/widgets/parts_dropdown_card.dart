import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ar_service.dart';

class PartsDropdownCard extends StatefulWidget {
  final List<Map<String, dynamic>>? parts;
  final String? modelPath;

  const PartsDropdownCard({
    Key? key,
    this.parts,
    this.modelPath,
  }) : super(key: key);

  @override
  PartsDropdownCardState createState() => PartsDropdownCardState();
}

class PartsDropdownCardState extends State<PartsDropdownCard> with TickerProviderStateMixin {
  int? _selectedPartId;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Sélectionner la première pièce par défaut si disponible
    if (widget.parts != null && widget.parts!.isNotEmpty) {
      _selectedPartId = widget.parts!.first['id'];
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _selectedPart {
    if (widget.parts == null) return null;
    try {
      return widget.parts!.firstWhere(
        (p) => p['id'] == _selectedPartId,
      );
    } catch (_) {
      return widget.parts!.isNotEmpty ? widget.parts!.first : null;
    }
  }

  // Méthode pour extraire le nom de la pièce
  String _getPartName(Map<String, dynamic> part) {
    return part['part_name']?.toString() ?? 'Pièce #${part['id'] ?? 'N/A'}';
  }

  // Méthode pour extraire l'URL du modèle 3D (submodel viewer)
  String? _getSubmodelViewerUrl(Map<String, dynamic> part) {
    if (part['submodel'] is Map && part['submodel']['viewer_url'] != null) {
      return part['submodel']['viewer_url'].toString();
    }
    return null;
  }

  // Méthode pour extraire l'URL du modèle 3D parent
  String? _getParentModelViewerUrl(Map<String, dynamic> part) {
    if (part['parent_model3d'] is Map && part['parent_model3d']['viewer_url'] != null) {
      return part['parent_model3d']['viewer_url'].toString();
    }
    return null;
  }

  // Méthode pour extraire la description
  String? _getPartDescription(Map<String, dynamic> part) {
    return part['description']?.toString().isNotEmpty == true
        ? part['description'].toString()
        : null;
  }

  // Méthode pour extraire le type d'intervention
  String? _getInterventionType(Map<String, dynamic> part) {
    return part['intervention_type_display']?.toString() ??
        part['intervention_type']?.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.parts == null || widget.parts!.isEmpty) {
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
                  Icon(Icons.build_circle, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'Parts',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Container(
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
                      'No parts have been found for this task.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                Icon(Icons.build_circle, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Parts',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.grey.shade800,
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    '${widget.parts!.length} part${widget.parts!.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Menu déroulant
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedPartId,
                  isExpanded: true,
                  hint: Text('Select a part'),
                  icon: Icon(Icons.keyboard_arrow_down, color: Colors.blue),
                  items: widget.parts!.map((part) {
                    return DropdownMenuItem<int>(
                      value: part['id'],
                      child: Row(
                        children: [
                          Icon(
                            _getPartTypeIcon(_getInterventionType(part) ?? ''),
                            color: _getInterventionTypeColor(_getInterventionType(part) ?? ''),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _getPartName(part),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (int? newId) {
                    if (newId != null) {
                      setState(() {
                        _selectedPartId = newId;
                      });
                      _animationController.reset();
                      _animationController.forward();
                    }
                  },
                ),
              ),
            ),

            SizedBox(height: 16),

            // Détails de la pièce sélectionnée
            if (_selectedPart != null)
              FadeTransition(
                opacity: _fadeAnimation,
                child: _buildPartDetails(_selectedPart!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartDetails(Map<String, dynamic> part) {
    final partName = _getPartName(part);
    final description = _getPartDescription(part);
    final interventionType = _getInterventionType(part);
    final submodelViewerUrl = _getSubmodelViewerUrl(part);
    final parentModelViewerUrl = _getParentModelViewerUrl(part);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nom de la pièce avec séquence
          Row(
            children: [
              Icon(
                _getPartTypeIcon(interventionType ?? ''),
                color: _getInterventionTypeColor(interventionType ?? ''),
                size: 24,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  partName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 12),

          // Description
          if (description != null && description.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.description, size: 16, color: Colors.grey.shade600),
                SizedBox(width: 8),
                Text(
                  'Description:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                description,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                ),
              ),
            ),
            SizedBox(height: 12),
          ],

          // Type d'intervention
          if (interventionType != null && interventionType.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.build, size: 16, color: Colors.grey.shade600),
                SizedBox(width: 8),
                Text(
                  'Intervention type:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getInterventionTypeColor(interventionType),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    interventionType,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
          ],

          // Boutons de visualisation 3D
          Column(
            children: [
              // Bouton pour voir le modèle 3D de la pièce spécifique
              if (submodelViewerUrl != null && submodelViewerUrl.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _launchUrl(submodelViewerUrl),
                    icon: Icon(Icons.view_in_ar, size: 18),
                    label: Text('See 3D Model'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),
              ],
              // Bouton pour lancer la vue AR
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _launchAR(context, part),
                  icon: Icon(Icons.camera, size: 18),
                  label: Text('Launch AR scene'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Message si aucun modèle 3D n'est disponible
          if ((submodelViewerUrl == null || submodelViewerUrl.isEmpty) &&
              (parentModelViewerUrl == null || parentModelViewerUrl.isEmpty)) ...[
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade600, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '3D model not available for this part.',
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
        ],
      ),
    );
  }

  // Méthodes utilitaires pour les icônes et couleurs selon le type d'intervention
  IconData _getPartTypeIcon(String interventionType) {
    switch (interventionType.toLowerCase()) {
      case 'remplacement':
      case 'replacement':
        return Icons.autorenew;
      case 'maintenance':
        return Icons.build_circle;
      case 'réparation':
      case 'repair':
        return Icons.engineering;
      case 'inspection':
        return Icons.search;
      case 'nettoyage':
      case 'cleaning':
        return Icons.cleaning_services;
      case 'lubrification':
      case 'lubrication':
        return Icons.oil_barrel;
      default:
        return Icons.build;
    }
  }

  Color _getInterventionTypeColor(String interventionType) {
    switch (interventionType.toLowerCase()) {
      case 'remplacement':
      case 'replacement':
        return Colors.red;
      case 'maintenance':
        return Colors.blue;
      case 'réparation':
      case 'repair':
        return Colors.orange;
      case 'inspection':
        return Colors.green;
      case 'nettoyage':
      case 'cleaning':
        return Colors.cyan;
      case 'lubrification':
      case 'lubrication':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  // Méthode pour lancer une URL avec notre schéma personnalisé
  Future<void> _launchUrl(String url) async {
    try {
      String customUrl = url.replaceFirst('http', 'cmms');
      final uri = Uri.parse(customUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to open the URL: $customUrl'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error while opening the URL: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error while opening the URL: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Remplacer la fonction _launchAR pour accepter le chemin du modèle de la pièce sélectionnée
void _launchAR(BuildContext context, Map<String, dynamic> part) async {
  try {
    String? modelPath;
    // Essayer d'obtenir le chemin du modèle de la pièce ou utiliser un chemin par défaut
    if (part['submodel'] is Map && part['submodel']['model_path'] != null) {
      modelPath = part['submodel']['model_path'].toString();
    }
    await ArService.launchArViewer(modelPath ?? 'models/damaged_helmet.glb');
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Impossible d’ouvrir la vue AR : $e')),
    );
  }
}
