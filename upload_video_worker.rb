class UploadVideoWorker
  include Sidekiq::Worker
	sidekiq_options :retry => false
	# Upload original video and make a compressed video copy with a watermark in Right bottom position
	# Also It will take the screenshots in between the video at predefined intervals. 
	# All of these the processes will run in background workers on Redis server using Sidekiq
	# When this video will be ready Admin will be notify using email 

	def perform video_id,temp_id,selected_image
		video = Video.find_by_id(video_id)
		if video
			upload_video_data(video,temp_id,selected_image)
			compress_video_with_watermark(video)
			# This mailer is sending an email to admin after video compressed with watermarked and uploaded over the server
			AdminMailer.video_mailer(video).deliver_now
		end
	end

	private
	
	# We are using Amazon s3 bucket storage to upload the video
	def upload_video_data video,temp_id,selected_image
		tmp = TempUpload.find_by_id(temp_id)
    if tmp
    	video_path = "public/"+ tmp.main_video.url
    	upload_screenshot_on_s3_bucket(tmp,video,selected_image)
    	upload_video_on_s3_bucket(video,tmp.main_video.url)
    	delete_temp_data(temp_id)
		end
	end

	def upload_video_on_s3_bucket video ,main_video_url
		directory = awsS3Connection.directories.get('tecorb-updated')
		video_path = "#{Rails.root}/public"+ main_video_url
		begin
		  vname = main_video_url.split('/').last
			@file_name = "#{ENV['HOSTINGMODE']}/Videos/v_#{video.id}/#{vname}"
			begin
				# preparing file to save (upload) to the aws s3 bucket
	  		s3_file = directory.files.new({
		      :key => @file_name,
		      :body => File.open(video_path),
		      :public => true
		    })
		    if s3_file.save
		    	# updating in database
	        video.update_attributes(:video_url=>s3_file.public_url)
	      end
		  rescue Exception => e
		  	p "Exception in uploading video on s3 bucket!"
  	  end
  	rescue Exception => e
  		p "Exception in the saved video!"
  	end
	end

	# Amazon s3 bucket storage configurations
	def awsS3Connection
    connection = Fog::Storage.new({
      :provider => "AWS",
      :aws_access_key_id => ENV["AWS_ACCESS_KEY_ID"],
      :aws_secret_access_key => ENV["AWS_SECRET_ACCESS_KEY"],
      :region => ENV["AWS_S3_REGION"],
      :path_style=>true
    })
  end

  # uploading the screenshoots on aws s3 bucket
  def upload_screenshot_on_s3_bucket(tmp,video,selected_image)
		directory = awsS3Connection.directories.get('tecorb-updated')
		imgs = []
		res = [tmp.screenshot_first,tmp.screenshot_second,tmp.screenshot_three]
		res.each_with_index do |r,ind|
	  	path = "#{Rails.root}/public" + "#{r}"
	  	count = ind+1
	  	@file_name = "#{ENV['HOSTINGMODE']}/Snapshots/v_#{video.id}-screenshot-#{count}.jpg"
	  	begin
	  		s3_file = directory.files.new({
		      :key => @file_name,
		      :body => File.open(path),
		      :public => true
		    })
		    if s3_file.save
	        imgs.push(s3_file.public_url)
	      end
		  rescue Exception => e
  		  imgs << nil
  	  end
	  end
	  # Saving uploaded screenshots urls in database
	  video.update_attributes(:image=>imgs[selected_image.to_i-1],selected_screenshot: selected_image.to_i,:screenshot_1=>imgs[0],:screenshot_2=>imgs[1],:screenshot_3=>imgs[2],:video_length=>tmp.video_length) 
  end

	def delete_temp_data video_id
		tmpu = TempUpload.find_by_id(video_id)
		path = "#{Rails.root}/public/uploads/temp_upload/main_video/#{tmpu.id}"
		begin
			if (File.exist?(path))
			  FileUtils.rm_rf("#{path}")
			  tmpu.delete
			end
		rescue => e
			p "#{e}"
		end
	end

	# Compressing and adding a logo as the watermark over the video and uploading at aws s3 bucket.
	def compress_video_with_watermark video
		directory = awsS3Connection.directories.get('tecorb-updated')
		begin
			movie = FFMPEG::Movie.new(video.video_url)
			options = {watermark: "#{Rails.root}/public/logo.png", resolution: "640x400", watermark_filter: {position: "LB", padding_x: 10, padding_y: 10}}
			savingPath = "#{Rails.root}/public/uploads/tmp/file#{video.id}.mp4"
			movie.transcode(savingPath, options)
			@file_name = "#{ENV['HOSTINGMODE']}/Videos/compressed/v_#{video.id}/is.mp4"
			s3_file = directory.files.new({
	      :key => @file_name,
	      :body => File.open(savingPath),
	      :public => true
	    })	
			if s3_file.save
        video.update_attributes(:sub_video_url=>s3_file.public_url)
      end
		rescue Exception => e
			p "xxxxxxxxxxxxxx error in compress: #{e}"
		end		
	end
end