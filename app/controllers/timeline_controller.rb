class TimelineController < ApplicationController
  include SortHelper
  include QueriesHelper
  include IssuesHelper

  menu_item :redmine_tx_timeline

  before_action :require_login
  before_action :find_project
  before_action :authorize

  def index
    @timeline_names = TimelineData.where( project_id: @project.id ).pluck(:name).uniq
    @timeline_data = TimelineData.active_for_project(@project.id)

    if @timeline_data && @timeline_data.categories.any?
      formatted_categories = format_timeline_categories(@timeline_data)
      @all_timelines = build_timeline_response_data(@timeline_data, formatted_categories, "Redmine 타임라인 데이터", @timeline_data.name)
    else
      @all_timelines = build_default_timeline_data("Redmine 타임라인 기본 데이터", @timeline_data&.name || "Default")
    end
  end

  def save_timeline_data
    begin
      name = (params[:name] || "Default").to_s.strip.truncate(255)
      data = JSON.parse(params[:timeline_data].to_s)

      unless data['categories'].is_a?(Array)
        raise ArgumentError, 'Invalid data format: categories must be an array'
      end

      TimelineData.transaction do
        timeline_data = TimelineData.lock.find_or_initialize_by(
          project_id: @project.id,
          name: name,
          is_active: true
        )

        timeline_data.assign_attributes(
          name: name,
          data: data.to_json,
          is_active: true
        )

        if timeline_data.save
          render json: {
            success: true,
            message: timeline_data.persisted? ? '타임라인 데이터가 성공적으로 업데이트되었습니다.' : '타임라인 데이터가 성공적으로 생성되었습니다.',
            timeline_id: timeline_data.id,
            updated_at: timeline_data.updated_at,
            is_new_record: timeline_data.previously_new_record?
          }
        else
          render json: {
            success: false,
            message: '저장에 실패했습니다.',
            errors: timeline_data.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

    rescue JSON::ParserError => e
      render json: {
        success: false,
        message: 'JSON 형식이 올바르지 않습니다.'
      }, status: :bad_request

    rescue => e
      Rails.logger.error "TimelineData 저장 중 예외 발생: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: {
        success: false,
        message: '서버 오류가 발생했습니다.',
        error_details: e.message
      }, status: :internal_server_error
    end
  end

  def load_timeline_data
    begin
      timeline_data = TimelineData.active_for_project(@project.id, params[:name])

      if timeline_data && timeline_data.categories.class == Array
        formatted_categories = format_timeline_categories(timeline_data)
        data = build_timeline_response_data(timeline_data, formatted_categories, "서버에서 로드한 Redmine 타임라인 데이터", timeline_data.name)

        render json: {
          success: true,
          name: timeline_data.name,
          data: data
        }
      else
        render json: {
          success: false,
          message: '저장된 타임라인 데이터가 없습니다.'
        }, status: :not_found
      end

    rescue => e
      Rails.logger.error "타임라인 데이터 로드 오류: #{e.message}"
      render json: {
        success: false,
        message: '데이터 로드 중 오류가 발생했습니다.'
      }, status: :internal_server_error
    end
  end

  def create_timeline
    begin
      name = params[:name]&.strip

      if name.blank?
        render json: {
          success: false,
          message: '타임라인 이름을 입력해주세요.'
        }, status: :bad_request
        return
      end

      existing_timeline = TimelineData.where(project_id: @project.id, name: name, is_active: true).first
      if existing_timeline
        render json: {
          success: false,
          message: '이미 같은 이름의 타임라인이 존재합니다.'
        }, status: :conflict
        return
      end

      timeline_data = TimelineData.create!(
        project_id: @project.id,
        name: name,
        is_active: true,
        data: build_default_timeline_data( "Redmine 타임라인 데이터", name ).to_json
      )

      render json: {
        success: true,
        message: "새 타임라인 '#{name}'이 성공적으로 생성되었습니다.",
        timeline_id: timeline_data.id,
        name: timeline_data.name
      }

    rescue => e
      Rails.logger.error "새 타임라인 생성 오류: #{e.message}"
      render json: {
        success: false,
        message: '타임라인 생성 중 오류가 발생했습니다.'
      }, status: :internal_server_error
    end
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  def authorize
    permission = case action_name
                 when 'save_timeline_data', 'create_timeline'
                   :edit_timeline
                 else
                   :view_timeline
                 end
    unless User.current.allowed_to?(permission, @project)
      deny_access
    end
  end

  def format_timeline_categories(timeline_data)
    return [] unless timeline_data&.categories&.any?

    # Batch load all issue IDs to avoid N+1 queries
    issue_ids = timeline_data.categories.flat_map do |category|
      (category['events'] || []).flat_map do |event|
        (event['schedules'] || []).map { |s| s['issue'] }.compact.select(&:present?)
      end
    end.uniq

    done_ratios = if issue_ids.any?
                    Issue.where(id: issue_ids).pluck(:id, :done_ratio).to_h
                  else
                    {}
                  end

    timeline_data.categories.map.with_index do |category, index|
      {
        name: category['name'] || '미분류',
        index: index,
        customColor: category['customColor'],
        events: (category['events'] || []).map do |event|
          {
            name: event['name'] || '이름 없음',
            schedules: (event['schedules'] || []).map do |schedule|
              format_schedule(schedule, done_ratios)
            end.compact
          }
        end.compact
      }
    end.compact
  end

  def format_schedule(schedule, done_ratios = {})
    begin
      start_date = Date.parse(schedule['startDate']) rescue nil if schedule['startDate'].present?
      end_date = Date.parse(schedule['endDate']) rescue nil if schedule['endDate'].present?

      issue_id = schedule['issue']
      done_ratio = issue_id.present? ? done_ratios[issue_id.to_i] : nil

      {
        name: schedule['name'] || '일정 없음',
        startDate: start_date&.strftime('%Y-%m-%d'),
        endDate: end_date&.strftime('%Y-%m-%d'),
        issue: issue_id || '',
        done_ratio: done_ratio,
        customColor: schedule['customColor']
      }
    rescue => e
      Rails.logger.warn "스케줄 파싱 오류: #{e.message}, 스케줄: #{schedule}"
      {
        name: schedule['name'] || '일정 없음',
        startDate: nil,
        endDate: nil,
        issue: schedule['issue'] || '',
        done_ratio: nil,
        customColor: schedule['customColor']
      }
    end
  end

  def build_timeline_response_data(timeline_data, categories, description, name = 'Default')
    {
      metadata: build_timeline_metadata(timeline_data, description, name),
      categories: categories
    }
  end

  def build_default_timeline_data(description, name = 'Default')
    build_timeline_response_data(nil, [], description, name)
  end

  def build_timeline_metadata(timeline_data, description, name = 'Default')
    {
      exportDate: timeline_data&.updated_at&.iso8601 || Time.current.iso8601,
      version: "1.0",
      name: name,
      description: description
    }
  end
end
