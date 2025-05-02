import 'package:flutter/material.dart';
import '../models/checkpoint_data.dart';

class CheckpointList extends StatelessWidget {
  final List<CheckpointData> checkpoints;
  final Function(int) onDelete;
  final Function(int, String) onNameChanged;
  final Function(int, double) onDistanceChanged;
  final String? editingCheckpointId;
  final bool isEditingName;
  final bool isEditingDistance;
  final List<FocusNode> nameFocusNodes;
  final List<FocusNode> distanceFocusNodes;

  const CheckpointList({
    super.key,
    required this.checkpoints,
    required this.onDelete,
    required this.onNameChanged,
    required this.onDistanceChanged,
    this.editingCheckpointId,
    this.isEditingName = false,
    this.isEditingDistance = false,
    required this.nameFocusNodes,
    required this.distanceFocusNodes,
  });

  String formatTime(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String formatPace(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: checkpoints.length,
      itemBuilder: (context, index) {
        final checkpoint = checkpoints[index];
        final isEditing = checkpoint.id == editingCheckpointId;

        return Card(
          child: ListTile(
            title: isEditing && isEditingName
                ? TextField(
                    focusNode: nameFocusNodes[index],
                    controller: TextEditingController(text: checkpoint.name),
                    onSubmitted: (value) => onNameChanged(index, value),
                    decoration: const InputDecoration(
                      labelText: 'Checkpoint Name',
                    ),
                  )
                : Text(checkpoint.name ?? 'Checkpoint ${index + 1}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isEditing && isEditingDistance
                    ? TextField(
                        focusNode: distanceFocusNodes[index],
                        controller: TextEditingController(
                            text: checkpoint.distance.toString()),
                        onSubmitted: (value) =>
                            onDistanceChanged(index, double.parse(value)),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Distance (km)',
                        ),
                      )
                    : Text('Distance: ${checkpoint.distance.toStringAsFixed(2)} km'),
                Text(
                    'Elevation: ${checkpoint.elevation.toStringAsFixed(0)}m (Gain: ${checkpoint.elevationGain.toStringAsFixed(0)}m, Loss: ${checkpoint.elevationLoss.toStringAsFixed(0)}m)'),
                Text(
                    'Time: ${formatTime(checkpoint.cumulativeTime)} (Leg: ${formatTime(checkpoint.timeFromPrevious)})'),
                Text(
                    'Pace: ${formatPace(checkpoint.baseGradeAdjustedPace)}/km (Adj: ${checkpoint.adjustmentFactor.toStringAsFixed(1)}s/km)'),
                Text(
                    'Grade Adjusted Distance: ${checkpoint.gradeAdjustedDistance.toStringAsFixed(2)} km (Cumulative: ${checkpoint.cumulativeGradeAdjustedDistance.toStringAsFixed(2)} km)'),
                Text(
                    'Carbs: ${checkpoint.legUnits} units (Total: ${checkpoint.cumulativeUnits} units)'),
                Text(
                    'Fluid: ${checkpoint.legFluidUnits} units (Total: ${checkpoint.cumulativeFluidUnits} units)'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => onDelete(index),
            ),
          ),
        );
      },
    );
  }
} 