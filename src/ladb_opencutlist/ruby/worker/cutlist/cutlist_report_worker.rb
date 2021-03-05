module Ladb::OpenCutList

  require_relative 'cutlist_cuttingdiagram_1d_worker'
  require_relative 'cutlist_cuttingdiagram_2d_worker'
  require_relative '../../model/report/report_def'
  require_relative '../../model/report/report_entry_def'

  class CutlistReportWorker

    def initialize(settings, cutlist)

      @hidden_group_ids = settings['hidden_group_ids']

      @cutlist = cutlist

      @cutlist_groups = @cutlist.groups.select { |group| group.material_type != MaterialAttributes::TYPE_UNKNOWN && !@hidden_group_ids.include?(group.id) }
      @remaining_step = @cutlist_groups.count

      @report_def = ReportDef.new

      # Setup caches
      @material_attributes_cache = {}
      @definition_attributes_cache = {}
      @model_unit_is_metric = DimensionUtils.instance.model_unit_is_metric

    end

    # -----

    def run
      return { :errors => [ 'default.error' ] } unless @cutlist

      unless @remaining_step == @cutlist_groups.count

        cutlist_group = @cutlist_groups[@cutlist_groups.count - @remaining_step - 1]
        report_group_def = @report_def.group_defs[cutlist_group.material_type]
        report_entry_def = nil

        case cutlist_group.material_type

        when MaterialAttributes::TYPE_SOLID_WOOD

          material_attributes = _get_material_attributes(cutlist_group.material_name)
          volumic_mass = material_attributes.f_volumic_mass
          std_price = _get_std_price_value([ cutlist_group.def.std_thickness ], material_attributes)

          report_entry_def = SolidWoodReportEntryDef.new(cutlist_group)
          report_entry_def.volumic_mass = volumic_mass
          report_entry_def.std_price = std_price
          report_entry_def.total_volume = cutlist_group.def.total_cutting_volume
          report_entry_def.total_mass = cutlist_group.def.total_cutting_volume * _u3_to_inch3(volumic_mass, cutlist_group.material_type) unless volumic_mass == 0
          report_entry_def.total_cost = cutlist_group.def.total_cutting_volume * _u3_to_inch3(std_price) unless std_price == 0

          report_group_def.entry_defs << report_entry_def
          report_group_def.total_volume += report_entry_def.total_volume

        when MaterialAttributes::TYPE_SHEET_GOOD

          material_attributes = _get_material_attributes(cutlist_group.material_name)
          volumic_mass = material_attributes.f_volumic_mass

          settings = Plugin.instance.get_model_preset('cutlist_cuttingdiagram2d_options', cutlist_group.id)
          settings['group_id'] = cutlist_group.id
          settings['bar_folding'] = false     # Remove unneeded computations
          settings['hide_part_list'] = true   # Remove unneeded computations

          if settings['std_sheet'] == ''
            std_sizes = material_attributes.std_sizes.split(';')
            settings['std_sheet'] = std_sizes[0] unless std_sizes.empty?
          end

          worker = CutlistCuttingdiagram2dWorker.new(settings, @cutlist)
          cuttingdiagram2d = worker.run

          report_entry_def = SheetGoodReportEntryDef.new(cutlist_group)
          report_entry_def.volumic_mass = volumic_mass
          report_entry_def.total_count = cuttingdiagram2d.summary.total_used_count
          report_entry_def.total_area = cuttingdiagram2d.summary.def.total_used_area

          cuttingdiagram2d.summary.sheets.each do |cuttingdiagram2d_summary_sheet|

            next unless cuttingdiagram2d_summary_sheet.is_used

            std_price = _get_std_price_value([ cutlist_group.def.std_thickness, Size2d.new(cuttingdiagram2d_summary_sheet.def.length, cuttingdiagram2d_summary_sheet.width) ], material_attributes)

            report_entry_sheet_def = SheetGoodReportEntrySheetDef.new(cuttingdiagram2d_summary_sheet)
            report_entry_sheet_def.std_price = std_price
            report_entry_sheet_def.total_mass = cuttingdiagram2d_summary_sheet.def.total_area * cutlist_group.def.std_thickness * _u3_to_inch3(volumic_mass) unless volumic_mass == 0
            report_entry_sheet_def.total_cost = cuttingdiagram2d_summary_sheet.def.total_area * _u2_to_inch2(std_price) unless std_price == 0
            report_entry_def.sheet_defs << report_entry_sheet_def

            report_entry_def.total_mass += report_entry_sheet_def.total_mass
            report_entry_def.total_cost += report_entry_sheet_def.total_cost

          end

          report_group_def.entry_defs << report_entry_def
          report_group_def.total_count = report_group_def.total_count + report_entry_def.total_count
          report_group_def.total_area += report_entry_def.total_area

        when MaterialAttributes::TYPE_DIMENSIONAL

          material_attributes = _get_material_attributes(cutlist_group.material_name)
          volumic_mass = material_attributes.f_volumic_mass

          settings = Plugin.instance.get_model_preset('cutlist_cuttingdiagram1d_options', cutlist_group.id)
          settings['group_id'] = cutlist_group.id
          settings['bar_folding'] = false     # Remove unneeded computations
          settings['hide_part_list'] = true   # Remove unneeded computations

          if settings['std_bar'] == ''
            std_sizes = material_attributes.std_lengths.split(';')
            settings['std_bar'] = std_sizes[0] unless std_sizes.empty?
          end

          worker = CutlistCuttingdiagram1dWorker.new(settings, @cutlist)
          cuttingdiagram1d = worker.run

          report_entry_def = DimensionalReportEntryDef.new(cutlist_group)
          report_entry_def.volumic_mass = volumic_mass
          report_entry_def.total_count = cuttingdiagram1d.summary.total_used_count
          report_entry_def.total_length = cuttingdiagram1d.summary.def.total_used_length

          cuttingdiagram1d.summary.bars.each do |cuttingdiagram1d_summary_bar|

            next unless cuttingdiagram1d_summary_bar.is_used

            std_price = _get_std_price_value([ Size2d.new(cutlist_group.def.std_dimension), cuttingdiagram1d_summary_bar.def.length ], material_attributes)

            report_entry_bar_def = DimensionalReportEntryBarDef.new(cuttingdiagram1d_summary_bar)
            report_entry_bar_def.std_price = std_price
            report_entry_bar_def.total_mass = cuttingdiagram1d_summary_bar.def.total_length * cutlist_group.def.std_width * cutlist_group.def.std_thickness * _u3_to_inch3(volumic_mass) unless volumic_mass == 0
            report_entry_bar_def.total_cost = cuttingdiagram1d_summary_bar.def.total_length * _u_to_inch(std_price) unless std_price == 0
            report_entry_def.bar_defs << report_entry_bar_def

            report_entry_def.total_mass += report_entry_bar_def.total_mass
            report_entry_def.total_cost += report_entry_bar_def.total_cost

          end

          report_group_def.entry_defs << report_entry_def
          report_group_def.total_count += report_entry_def.total_count
          report_group_def.total_length += report_entry_def.total_length

        when MaterialAttributes::TYPE_EDGE

          material_attributes = _get_material_attributes(cutlist_group.material_name)
          volumic_mass = material_attributes.f_volumic_mass
          std_price = _get_std_price_value([ cutlist_group.def.std_dimension.to_l ], material_attributes)

          report_entry_def = EdgeReportEntryDef.new(cutlist_group)
          report_entry_def.volumic_mass = volumic_mass
          report_entry_def.std_price = std_price
          report_entry_def.total_length = cutlist_group.def.total_cutting_length
          report_entry_def.total_mass = cutlist_group.def.total_cutting_volume * _u3_to_inch3(volumic_mass) unless volumic_mass == 0
          report_entry_def.total_cost = cutlist_group.def.total_cutting_length * _u_to_inch(std_price) unless std_price == 0

          report_group_def.entry_defs << report_entry_def
          report_group_def.total_length += report_entry_def.total_length

        when MaterialAttributes::TYPE_ACCESSORY

          report_entry_def = AccessoryReportEntryDef.new(cutlist_group)
          report_entry_def.total_count = cutlist_group.def.part_count

          cutlist_group.parts.each do |cutlist_part|

            if cutlist_part.is_a?(FolderPart)
              cutlist_part.children.each { |cutlist_child_part|
                _compute_accessory_part(cutlist_child_part, report_entry_def)
              }
            else
              _compute_accessory_part(cutlist_part, report_entry_def)
            end

          end

          report_group_def.entry_defs << report_entry_def
          report_group_def.total_count += report_entry_def.total_count

        end

        unless report_entry_def.nil?

          report_group_def.total_mass += report_entry_def.total_mass
          report_group_def.total_cost += report_entry_def.total_cost

          @report_def.total_mass += report_entry_def.total_mass
          @report_def.total_cost += report_entry_def.total_cost

        end

      end

      if @remaining_step > 0
        response = {
            :remaining_step => @remaining_step,
        }
        @remaining_step = @remaining_step - 1
      else

        # Errors
        if @report_def.group_defs.values.select { |group_def| !group_def.entry_defs.empty? }.length == 0
          @report_def.errors << 'tab.cutlist.report.error.no_typed_material_parts'
        end

        # Create the report
        report = @report_def.create_report

        response = report.to_hash

      end

      response
    end

    # -----

    private

    # -- Cache Utils --

    # MaterialAttributes

    def _get_material_attributes(material_name)
      material = Sketchup.active_model.materials[material_name]
      key = material ? material.name : '$EMPTY$'
      unless @material_attributes_cache.has_key? key
        @material_attributes_cache[key] = MaterialAttributes.new(material)
      end
      @material_attributes_cache[key]
    end

    # DefinitionAttributes

    def _get_definition_attributes(definition_name)
      definition = Sketchup.active_model.definitions[definition_name]
      key = definition ? definition.name : '$EMPTY$'
      unless @definition_attributes_cache.has_key? key
        @definition_attributes_cache[key] = DefinitionAttributes.new(definition, true)
      end
      @definition_attributes_cache[key]
    end

    # -----

    def _compute_accessory_part(cutlist_part, report_entry_def)

      report_entry_part_def = AccessoryReportEntryPartDef.new(cutlist_part)
      report_entry_def.part_defs << report_entry_part_def

      definition_attributes = _get_definition_attributes(cutlist_part.def.definition_id)

      unit_mass = definition_attributes.f_unit_mass
      unless unit_mass == 0
        report_entry_part_def.unit_mass = unit_mass
        report_entry_part_def.total_mass = unit_mass.to_f * cutlist_part.def.count
        report_entry_def.total_mass = report_entry_def.total_mass + report_entry_part_def.total_mass
      end

      unit_price = definition_attributes.f_unit_price
      unless unit_price == 0
        report_entry_part_def.unit_price = unit_price
        report_entry_part_def.total_cost = unit_price.to_f * cutlist_part.def.count
        report_entry_def.total_cost = report_entry_def.total_cost + report_entry_part_def.total_cost
      end

    end

    def _get_std_price_value(entry_dim, material_attributes)

      l_std_prices = material_attributes.l_std_prices
      l_std_prices.each do |std_price|

        if std_price[:dim] == entry_dim
          return std_price[:val]
        end

      end

      l_std_prices[0][:val]
    end

    INCH_TO_M = 1.to_m
    INCH2_TO_M2 = INCH_TO_M * INCH_TO_M
    INCH3_TO_M3 = INCH2_TO_M2 * INCH_TO_M

    def _u3_to_inch3(f3, material_type = nil)
      if @model_unit_is_metric
        f3 * INCH3_TO_M3
      else
        if material_type == MaterialAttributes::TYPE_SOLID_WOOD
          f3 / 144
        else
          f3 / 1728
        end
      end
    end

    def _u2_to_inch2(f2)
      if @model_unit_is_metric
        f2 * INCH2_TO_M2
      else
        f2 / 144
      end
    end

    def _u_to_inch(f)
      if @model_unit_is_metric
        f * INCH_TO_M
      else
        f
      end
    end

  end

end
