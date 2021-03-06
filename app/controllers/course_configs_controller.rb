#
# Copyright (C) 2014 - present Instructure, Inc.
#
# This file is part of Rollcall.
#
# Rollcall is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Rollcall is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

class CourseConfigsController < ApplicationController
  before_action :can_grade

  respond_to :json

  def create
    config = CourseConfig.new(course_config_params)
    config.tool_consumer_instance_guid = tool_consumer_instance_guid
    saved = config.save if authorized_to_update_config?(config)
    resubmit_all_grades!(config) if saved && config.needs_regrade
    respond_with config
  end

  def update
    if config = CourseConfig.find_by(id: params[:id])
      config.attributes = course_config_params
      saved = config.save if authorized_to_update_config?(config)
      resubmit_all_grades!(config) if saved && config.needs_regrade
      respond_with config
    else
      head :not_found
    end
  end

  protected

  def authorized_to_update_config?(config)
    config.course_id && load_and_authorize_course(config.course_id)
  end

  def course_sections(config)
    load_and_authorize_sections(config.course_id)
  end

  def course_config_params
    params.require(:course_config).permit(:course_id, :tardy_weight, :view_preference)
  rescue ActionController::ParameterMissing
    {}
  end

  def resubmit_all_grades!(config)
    sections = course_sections(config)
    section_ids = Hash[sections.map{|s| [s.id, s.students.map(&:id)]}]
    grade_params = {
      canvas_url: canvas_url,
      user_id: user_id,
      course_id: config.course_id,
      section_ids: section_ids,
      tool_consumer_instance_guid: tool_consumer_instance_guid,
      identifier: SecureRandom.hex(32),
      tool_launch_url: launch_url
    }

    Resque.enqueue(AllGradeUpdater, grade_params)
  end
end
