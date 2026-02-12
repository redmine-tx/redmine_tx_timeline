class TimelineData < ApplicationRecord
  self.table_name = 'timeline_data'

  MAX_DATA_SIZE = 5.megabytes

  belongs_to :project

  validates :project_id, presence: true
  validates :data, presence: true
  validates :name, presence: true, length: { maximum: 255 }
  validate :validate_data_size
  validate :validate_json_structure

  # JSON 데이터를 파싱하여 반환
  def parsed_data
    @parsed_data ||= JSON.parse(data)
  rescue JSON::ParserError
    {}
  end

  # JSON 데이터 접근을 위한 메서드
  def categories
    parsed_data['categories'] || []
  end

  def metadata
    parsed_data['metadata'] || {}
  end

  # JSON 데이터 설정
  def set_data(hash_data)
    self.data = hash_data.to_json
  end

  # 프로젝트별 활성 타임라인 가져오기
  def self.active_for_project(project_id, name = 'Default')
    timelines = where(project_id: project_id, is_active: true, name: name).order(updated_at: :desc)
    timelines.first
  end

  private

  def validate_data_size
    if data.present? && data.bytesize > MAX_DATA_SIZE
      errors.add(:data, "데이터 크기가 #{MAX_DATA_SIZE / 1.megabyte}MB를 초과합니다.")
    end
  end

  def validate_json_structure
    return if data.blank?
    parsed = JSON.parse(data) rescue nil
    if parsed.nil?
      errors.add(:data, '올바른 JSON 형식이 아닙니다.')
      return
    end
    unless parsed.is_a?(Hash) && parsed['categories'].is_a?(Array)
      errors.add(:data, 'categories 배열이 필요합니다.')
    end
  end
end
